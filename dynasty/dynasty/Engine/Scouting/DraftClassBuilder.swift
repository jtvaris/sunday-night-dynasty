import Foundation

/// Draft-class generator — "talent curve first, positions second, attributes last".
///
/// Implements `docs/DRAFT_CLASS_OVERHAUL_PLAN.md` §2 (steps 1–10) against the
/// calibration targets in `docs/DRAFT_NFL_REFERENCE.md`. The old generator built
/// a body first, then derived a round from `trueOverall × positionalDraftValue`,
/// which degenerated into a pure position sort (every QB ahead of every RB) and
/// compressed the whole class into a 60–69 overall band.
///
/// The pipeline here runs the other way round:
///
/// 1. **Blueprint** — per-class positional strength `s ~ N(1, 0.15)`, a QB
///    first-round histogram, per-position class/round-band counts with clamps.
/// 2. **Talent backbone** — every ordered slot `r` gets a true-ability target
///    `96.5 − 5.2·ln(r + 1.5) + ε`, so slot *is* talent.
/// 3. **Archetype & age** — Polished / Balanced / Raw, position-biased.
/// 4. **Attributes** — mental and physical sampled from the shared
///    `PositionPhysicalProfile` priors scaled toward the talent target, then the
///    position-skill average is *solved* so `trueOverall` lands on the target.
/// 5. **Potential** — `trueOverall +` the remaining runway to his position's
///    peak window, scaled by what his grade still projects (`drawUpside`).
/// 6. **Learning**, 7. **college production**, 8. **NFL readiness**.
enum DraftClassBuilder {

    /// Generator revision stamped onto every prospect (`generatorVersion`).
    static let currentGeneratorVersion = 2

    // MARK: - Class strength (UI / news compatible surface)

    /// Per-class positional strength. Replaces the old discrete strong/weak
    /// lists with a continuous multiplier, but still exposes the 2–3 strongest
    /// and weakest positions so news and UI copy keep working.
    struct DraftClassStrength {
        /// Continuous multiplier per position, `N(1, 0.15)` clamped [0.70, 1.35].
        let multipliers: [Position: Double]

        /// The 3 strongest positions of the class (multiplier ≥ 1.12).
        var strongPositions: Set<Position> {
            Set(multipliers.filter { $0.value >= 1.12 }
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { $0.key })
        }

        /// The 3 weakest positions of the class (multiplier ≤ 0.88).
        var weakPositions: Set<Position> {
            Set(multipliers.filter { $0.value <= 0.88 }
                .sorted { $0.value < $1.value }
                .prefix(3)
                .map { $0.key })
        }
    }

    /// The strength profile of the most recently generated class, for news copy.
    static private(set) var lastClassStrength: DraftClassStrength?

    // MARK: - Public API

    /// Builds a complete draft class.
    /// - Parameters:
    ///   - count: Class size (default 350, matching the shipped call sites).
    ///   - careerID: the save this class belongs to. Only ever used to seed the
    ///     market's consensus error (`consensusError`); `nil` falls back to the
    ///     prospect UUID alone, which is already unique per save.
    /// - Returns: The prospects (shuffled) and the class strength profile.
    @discardableResult
    static func build(
        count: Int = 350,
        careerID: UUID? = nil
    ) -> (prospects: [CollegeProspect], strength: DraftClassStrength) {
        let ordered = buildOrdered(count: count, careerID: careerID)
        var prospects = ordered.prospects
        prospects.shuffle()
        return (prospects, ordered.strength)
    }

    /// Board-ordered build: identical generation, but the prospects come back in
    /// slot order (slot 1 first) together with each slot's grade band — the two
    /// facts `build` throws away when it shuffles. Used by the balance harness's
    /// `draftclass` scenario to validate the band distributions
    /// (`tools/balance-harness`, plan §7); the shipped call sites use `build`.
    static func buildOrdered(
        count: Int = 350,
        careerID: UUID? = nil
    ) -> (prospects: [CollegeProspect], bands: [Int], strength: DraftClassStrength) {
        let size = max(60, count)

        // --- Step 1: blueprint -------------------------------------------------
        let strengths = drawGroupStrengths()
        let groupCounts = allocateGroupCounts(size: size, strengths: strengths)
        let bandSizes = bandSizes(for: size)
        let r1Counts = allocateFirstRound(
            capacity: bandSizes[0],
            groupCounts: groupCounts,
            strengths: strengths
        )
        var tokens = buildSlotTokens(
            groupCounts: groupCounts,
            r1Counts: r1Counts,
            bandSizes: bandSizes
        )
        enforceInvariants(tokens: &tokens)
        shuffleWithinBands(tokens: &tokens, bandSizes: bandSizes)

        // --- Step 2: talent backbone ------------------------------------------
        // Some drafts are simply better than others. The draw is truncated at
        // ±1σ: an untruncated N(0, 0.8) moves the whole curve far enough that a
        // 2σ-poor year drops below the plan's "5–14 A-range prospects per class"
        // floor (§7.4) — measured 3 in the worst of 200 classes. Truncation keeps
        // the year-to-year swing without producing a starless draft.
        let classQuality = PositionPhysicalProfile.truncatedGaussian(mean: 0, sd: 0.8, limit: 1.0)

        var prospects: [CollegeProspect] = []
        prospects.reserveCapacity(tokens.count)

        // Every premium group's best prospect carries a marquee skill: even in a
        // weak year the top corner or edge is somebody's blue-chip trait (plan
        // §7.5 — "≥1 per class per premium position group at 88+"). Without this
        // the guarantee is left to chance, and a group whose R1 grades all land
        // in slots 13–40 can miss it.
        var forcedEliteSlots = Set<Int>()
        for group in PositionGroup.allCases where premiumTraitGroups.contains(group) {
            if let index = tokens.firstIndex(where: { $0.group == group }) {
                forcedEliteSlots.insert(index + 1)
            }
        }

        // Draw every slot's talent target up front so a blue-chip floor can be
        // enforced before attributes are solved: every real draft produces a
        // consensus top-5, so a class may never carry fewer than 5 A-range (85+)
        // prospects (plan §7.4a's lower bound). A poor class-quality draw plus
        // unlucky ε can leave only 4 targets above the line (~1 class in ~800,
        // an extreme-value statistic no per-slot σ tuning can pin down) — lift
        // the nearest misses to 86 instead (the skill solver lands targets ±1,
        // so realized trueOverall stays ≥ 85).
        var talents = (0..<tokens.count).map { index in
            talentTarget(slot: index + 1, classSize: size, classQuality: classQuality)
        }
        let blueChipTarget = 86.0
        let blueChips = talents.filter { $0 >= blueChipTarget }.count
        if blueChips < 5 {
            let lifts = talents.enumerated()
                .filter { $0.element < blueChipTarget }
                .sorted { $0.element > $1.element }
                .prefix(5 - blueChips)
            for (index, _) in lifts {
                talents[index] = Double.random(in: 86.0...86.9)
            }
        }

        // The draft feed abbreviates to "N. Abernathy" and the board shows only
        // the full name, so a duplicate is unresolvable by any screen that
        // displays it — the draw has to be rejection-sampled.
        //
        // This set carries the COHORT half of that: it is what holds the
        // surname and given-name quotas ("no more than two Abernathys on one
        // board"), and it is deliberately empty at the top of every class
        // because a quota counts what is on THIS list. The league half — the
        // rookie who arrives already sharing a name with a man on his own
        // roster — is `RandomNameGenerator`'s own ledger, which spans classes
        // and needs nothing from here.
        var usedNames: Set<String> = []

        for (index, token) in tokens.enumerated() {
            let slot = index + 1
            let band = token.band
            let talent = talents[index]
            let prospect = makeProspect(
                position: token.position,
                slot: slot,
                band: band,
                talent: talent,
                forceEliteTrait: forcedEliteSlots.contains(slot),
                usedNames: &usedNames
            )
            prospects.append(prospect)
        }

        var strengthMultipliers: [Position: Double] = [:]
        for group in PositionGroup.allCases {
            let value = strengths[group] ?? 1.0
            for position in group.members {
                strengthMultipliers[position] = value
            }
        }
        let strength = DraftClassStrength(multipliers: strengthMultipliers)
        lastClassStrength = strength

        assignPreviewFaces(to: prospects)
        assignConsensusProjections(prospects, tokens: tokens, careerID: careerID)
        assignDeclarationWindow(prospects)

        return (prospects, tokens.map { $0.band }, strength)
    }

    /// Gives every prospect a portrait for the Big Board / draft panels.
    ///
    /// Deliberately `previewFace` (non-reserving): a class is 350 prospects and
    /// only ~30 of them are ever signed, so reserving would burn a sixth of the
    /// whole face pool every single spring. The pick still prefers FREE faces,
    /// so the portrait a user scouted normally survives the draft unchanged —
    /// `DraftEngine.copyProspectMetadata` claims it for real at signing.
    private static func assignPreviewFaces(to prospects: [CollegeProspect]) {
        for prospect in prospects where prospect.faceID == nil {
            prospect.faceID = FaceLibrary.shared.previewFace(
                personID: prospect.id,
                role: .player,
                age: prospect.age,
                position: prospect.position
            )
        }
    }

    /// Positions whose best prospect always shows at least one A-range trait.
    static let premiumTraitGroups: Set<PositionGroup> = [.qb, .wr, .ot, .edge, .cb, .dt]

    // MARK: - The market's own error (task #78)
    //
    // Before this the PUBLIC projected round WAS the generator's grade band —
    // `draftProjection = min(7, band)`, the same band the talent backbone was
    // drawn from. The consensus was therefore omniscient: the media had every
    // man in exactly the round his hidden rating deserved, so a "bust" could
    // only ever be a development outcome and a "steal" could only ever be a
    // prospect the user had scouted and nobody else had. Scouting could not
    // beat the market, because there was no market to beat.
    //
    // The public board is now `trueOverall + consensusError`, re-slotted through
    // the SAME band capacities. Two properties follow, both load-bearing:
    //
    //  * the multiset of `draftProjection` values over the class is EXACTLY
    //    preserved (it is a permutation of the generator's own band array), so
    //    every downstream consumer — `applyProjectionDrift`'s zero-sum swap,
    //    `ProspectFog.consensusBand`, `DraftIntel.publicOVREstimate`, the
    //    rookie-band fallbacks — sees the class shape it was calibrated on; and
    //  * the generator's `bands` return value is untouched, so the whole
    //    `draftclass` gate (which measures TRUE bands) is insulated by
    //    construction. The error moves opinion, never talent.

    /// σ of the consensus's read on a prospect's current level, in OVR points.
    ///
    /// Persona-free on purpose: `AIDraftPerception` gives each of the 31 clubs
    /// its own σ off its GM archetype, because that is a statement about one
    /// front office. This is the *aggregate* of every front office, every
    /// analyst and every draftnik in one number, and it sits where the balanced
    /// archetype does (4.5) plus a little for the fact that a consensus is an
    /// average of opinions formed months before the workouts.
    static let consensusSigma = 5.0

    /// Share of prospects the consensus is simply wrong about. `AIDraftPerception`'s
    /// own rate and band, and for the same reason: a Gaussian at σ ≈ 5 almost
    /// never moves a man 20 board slots, and it is the 20-slot misses that make
    /// a top-10 bust and a fifth-round steal exist at all.
    static let consensusFatTailRate = 0.07
    static let consensusFatTailMin = 8.0
    static let consensusFatTailMax = 14.0

    /// The class-wide seed the market draw folds the prospect UUID against when
    /// no career is supplied (previews, the balance harness, a legacy call
    /// site). Fixed, so the draw stays reproducible; the prospect UUID is
    /// already unique per save, so this loses nothing but the audit trail.
    private static let marketSeedID = UUID(uuidString: "5A4B0000-0000-4000-A000-4D41524B4554")
        ?? UUID()

    /// The consensus's signed error on one prospect, in OVR points.
    ///
    /// Deterministic per `(careerID, prospectID)` — the same save always
    /// produces the same wrong board, across relaunches and re-entries into the
    /// draft room. Uses `AIDraftPerception.pairSeed` (the FNV/SplitMix UUID
    /// fold) rather than `hashValue`, whose seed is randomised per process.
    static func consensusError(careerID: UUID?, prospectID: UUID) -> Double {
        var rng = SeededLeagueRandom(
            seed: AIDraftPerception.pairSeed(
                teamID: careerID ?? marketSeedID,
                prospectID: prospectID
            )
        )
        // Box-Muller off the repo RNG; `u1` floored away from 0 because log(0)
        // is −inf and SplitMix64 can legitimately return it.
        let u1 = max(1e-12, Double.random(in: 0..<1, using: &rng))
        let u2 = Double.random(in: 0..<1, using: &rng)
        let z = (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
        var error = z * consensusSigma

        if Double.random(in: 0..<1, using: &rng) < consensusFatTailRate {
            let magnitude = Double.random(
                in: consensusFatTailMin...consensusFatTailMax, using: &rng
            )
            error += (Double.random(in: 0..<1, using: &rng) < 0.5 ? -1.0 : 1.0) * magnitude
        }
        return error
    }

    /// What the consensus can grade a `limitedSample` prospect at, in OVR
    /// points (task #181).
    ///
    /// Anchored on the USAGE record rather than on the man, because the usage
    /// record is literally everything the room has: 89 snaps of a redshirt
    /// sophomore. `applyBuriedUsage` spans the buried production score over
    /// 20…66 by construction, and this maps that span onto 38…64 — from
    /// "nobody in the building has heard of him" to the bottom of the
    /// draftable board, which is where a man with one spot start belongs
    /// however good he turns out to be.
    ///
    /// The top of the range is the load-bearing number: 64 sits below
    /// `talentTarget(slot: 224)` ≈ 66–69, i.e. inside the last two rounds, so
    /// "the market never puts a prospect it has not seen in the early rounds"
    /// holds BY CONSTRUCTION rather than by tuning. See `usageErrorDamping`
    /// for the other half of that guarantee.
    static func usageAnchor(for prospect: CollegeProspect) -> Double {
        let score = Double(min(66, max(20, prospect.collegeProductionScore)))
        return 38.0 + (score - 20.0) * (26.0 / 46.0)
    }

    /// How much of the ordinary consensus error survives on a man nobody has
    /// tape on.
    ///
    /// An opinion formed from 89 snaps cannot be a strong opinion in either
    /// direction, and the fat tail especially: `consensusFatTail*` models a
    /// room that watched a season of film and got it badly wrong, and there is
    /// no season of film here to get wrong. At 0.25 the σ = 5 draw becomes
    /// σ = 1.25 and the 8–14 point fat tail becomes 2–3.5, so the worst case a
    /// buried prospect can board at is `64 + 0.25·(3σ + 14)` ≈ 71 — still below
    /// the round-4 line.
    static let usageErrorDamping = 0.25

    /// How far the consensus marks a man DOWN for never having played, in OVR
    /// points — `trueOverall − usageAnchor`.
    ///
    /// Folded into `consensusErrorStored` rather than applied to the board
    /// ordering alone, on purpose: `consensusOverall` is `trueOverall + error`
    /// and is what `ProspectFog` bands and `DraftIntel.publicOVREstimate` read,
    /// so suppressing the projection without suppressing the grade would have
    /// printed a round-6 projection beside a first-round public grade. The
    /// market's read is ONE read.
    ///
    /// Note what this does to the two ends of the buried cohort. A first-round
    /// talent with 135 snaps (true 83, production 45) boards at ~52; a
    /// genuinely middling one with the same record (true 64) boards at ~52 as
    /// well. On the PUBLIC board they are indistinguishable — which is exactly
    /// the discrimination the scouting spend is being sold for. The scouting
    /// report path reads `trueAttributes` and is untouched.
    ///
    /// Deterministic: both inputs are stored fields, so the same class produces
    /// the same suppression on every relaunch.
    static func usageSuppression(for prospect: CollegeProspect) -> Double {
        guard prospect.hasLimitedCollegeSample else { return 0 }
        return max(0, Double(prospect.trueOverall) - usageAnchor(for: prospect))
    }

    /// Draws the market's error on every prospect, stores it, and rebuilds
    /// `draftProjection` as the PUBLIC board rather than the true grade band.
    ///
    /// The band array is used verbatim as the slot ladder: public board slot `k`
    /// inherits the band the generator gave generation slot `k`. Because that
    /// array is non-decreasing and the assignment is a permutation of it, the
    /// number of round-1 projections, round-7 projections and everything between
    /// is bit-for-bit what it was before this pass existed.
    ///
    /// One repair pass runs on top: a kicker, punter or fullback may never carry
    /// a projection earlier than his group's `earliestBand`, however well the
    /// market happens to have read him. That is not fog, it is how the position
    /// is valued — no amount of consensus error puts a punter in round 1.
    private static func assignConsensusProjections(
        _ prospects: [CollegeProspect],
        tokens: [SlotToken],
        careerID: UUID?
    ) {
        guard prospects.count == tokens.count, !prospects.isEmpty else { return }

        var perceived = [Double](repeating: 0, count: prospects.count)
        for index in prospects.indices {
            let prospect = prospects[index]
            var error = consensusError(careerID: careerID, prospectID: prospect.id)
            if prospect.hasLimitedCollegeSample {
                // No tape: the read collapses onto the usage anchor and what
                // is left of the ordinary error is damped (task #181).
                error = error * usageErrorDamping - usageSuppression(for: prospect)
            }
            prospect.consensusErrorStored = Int(error.rounded())
            perceived[index] = Double(prospect.trueOverall) + error
        }

        // UUID tie-break: `sorted(by:)` is not stable, and two men on identical
        // perceived grades must not be ordered by an array position that is not
        // itself stable across a store round-trip.
        var order = prospects.indices.sorted { lhs, rhs in
            if perceived[lhs] != perceived[rhs] { return perceived[lhs] > perceived[rhs] }
            return prospects[lhs].id.uuidString < prospects[rhs].id.uuidString
        }

        let bandBySlot = tokens.map { $0.band }
        for slot in order.indices {
            let group = tokens[order[slot]].group
            guard group.earliestBand > bandBySlot[slot] else { continue }
            // Swap him with the first man deeper on the public board who can
            // legally take this slot, and whose own slot he can legally take.
            let swap = (slot + 1..<order.count).first { candidate in
                tokens[order[candidate]].group.earliestBand <= bandBySlot[slot]
                    && group.earliestBand <= bandBySlot[candidate]
            }
            guard let swap else { continue }
            order.swapAt(slot, swap)
        }

        for (slot, index) in order.enumerated() {
            let projection = min(7, bandBySlot[slot])
            prospects[index].draftProjection = projection
            prospects[index].projectionAtGeneration = projection
        }
    }

    /// Opens the January declaration window (task #78, finding S11).
    ///
    /// Seniors are in the draft whether they like it or not, so they are marked
    /// `.declared` at birth. Everybody else starts `.undecided` and stays there
    /// until `ScoutingEngine.generateDeclarations` runs in January — which is
    /// the fact the autumn board had no way to render, because
    /// `isDeclaringForDraft` carries a model default of `true` and the board read
    /// that as a lock.
    ///
    /// `isDeclaringForDraft` itself is deliberately left alone: a November mock
    /// draft does include the juniors everybody expects to come out, and the
    /// declaration window is the only thing allowed to move that flag.
    private static func assignDeclarationWindow(_ prospects: [CollegeProspect]) {
        for prospect in prospects {
            prospect.declarationStatusRaw = prospect.age >= CollegeProspect.seniorAge
                ? DeclarationStatus.declared.rawValue
                : DeclarationStatus.undecided.rawValue
        }
    }

    // MARK: - Step 2: talent curve

    /// Per-slot talent noise. Plan §2 step 2 quotes `ε ~ N(0, 1.2)`, but plan §7
    /// item 4 also requires `σ(trueOverall) ≥ 1.5` *inside every band*. Bands R3–R7
    /// are 38–55 slots wide on the flat part of the log curve, so the slot spread
    /// alone contributes only σ ≈ 0.5–0.6 — at ε = 1.2 the measured within-band σ
    /// is 1.30–1.44 and the §7.4 assert fails. ε = 1.5 satisfies it with margin
    /// (measured 1.55–1.70) and leaves the curve itself untouched.
    static let talentNoiseSD: Double = 1.5

    /// Talent noise for the very top of the board. §7 item 4 *also* fixes the
    /// number of A-range (85+) prospects per class at 5–14, and that count is
    /// decided entirely by the ~15 slots whose target sits near the 85 line: at
    /// ε = 1.5 the count carries σ ≈ 1.5, so [5,14] is barely ±3σ and roughly one
    /// class in 200 falls outside it (measured 4 and 15). Slots 1–20 therefore
    /// draw a tighter ε — band R1 still spans 92 → 79 on the curve alone, so its
    /// within-band σ stays ≈ 3.5, far above the §7.4 floor.
    static let talentNoiseSDTop: Double = 0.8
    static let talentNoiseTopSlots = 20

    /// True current-ability target for an ordered slot.
    ///
    /// `96.5 − 5.2·ln(r + 1.5) + N(0, 1.5)` plus the class-quality shift.
    /// ≈ #1 92 · #10 84 · #28 79 · #100 72.5 · #224 68.
    ///
    /// Calibration deviation: the plan quotes both this formula *and* "#350 ≈
    /// 60–64", which the bare curve cannot reach (it bottoms out at 66). A
    /// linear taper applied only past the last drafted slot (224 of 350) closes
    /// that gap — every drafted slot keeps the formula verbatim.
    static func talentTarget(slot: Int, classSize: Int, classQuality: Double) -> Double {
        let base = 96.5 - 5.2 * log(Double(slot) + 1.5)
        let draftedSlots = Int(Double(classSize) * 0.64)   // 224 of 350
        let taper = slot > draftedSlots ? Double(slot - draftedSlots) * 0.03 : 0
        let sd = slot <= talentNoiseTopSlots ? talentNoiseSDTop : talentNoiseSD
        let noise = PositionPhysicalProfile.gaussian(mean: 0, sd: sd)
        return base - taper + noise + classQuality
    }

    // MARK: - Step 3–8: one prospect

    private static func makeProspect(
        position: Position,
        slot: Int,
        band: Int,
        talent: Double,
        forceEliteTrait: Bool = false,
        usedNames: inout Set<String>
    ) -> CollegeProspect {
        let target = min(97.0, max(30.0, talent))

        // --- Step 3: archetype & age ------------------------------------------
        let archetype = drawArchetype(for: position)
        let age = drawAge(archetype: archetype)

        // --- Step 4: attributes from talent -----------------------------------
        // Physical and mental both scale with talent (they carry 30 % / 20 % of
        // the overall formula); the position-skill average is then solved so
        // `trueOverall` lands on the target.
        //
        // `athleticism` is measured against the league baseline, NOT against the
        // position's own average: it becomes the *level shift* applied to the
        // position priors, so a receiver still runs like a receiver and a guard
        // like a guard. Anchoring it to the position average instead would drag
        // every position's speed toward the same number and knock the combine
        // 40-times off the reference by up to 0.08 s.
        //
        // Slope calibration: at 0.90 the level shift reached +18 points against
        // priors whose σ is 4–5, i.e. +3.5…+4.5σ instead of the plan §4 "+0.5σ…
        // +1σ for top slots". Every fast position simply pinned on the 99 clamp
        // — measured 55 % of top-12 corners and 52 % of top-12 receivers at
        // speed *exactly* 99, so the top of the board carried no ordering to
        // feed the combine. 0.72 with the intercept re-solved at the class-mean
        // talent (≈71.5) keeps the class average athleticism byte-for-byte where
        // it was — only the tails move — and `PositionPhysicalProfile.softCeiling`
        // handles what still overshoots.
        var athleticism = 0.72 * target + 17.9 + archetype.physicalTilt
        var mentalLevel = 0.85 * target + 8.0 + archetype.mentalTilt
        // Top-40 slots read the game better; UDFAs read it worse (plan §4).
        if slot <= 40 { mentalLevel += 6 } else if band >= 8 { mentalLevel -= 3 }

        // Analytic pre-check: if the solved position average would fall outside
        // the attainable band, move both level targets so it lands back inside.
        let physProfile = PositionPhysicalProfile.profile(for: position)
        var expectedPhysical = physProfile.meanAverage
            + (athleticism - PositionPhysicalProfile.baseLevel)
        var predictedPos = solvePositionAverage(
            target: target,
            physicalAverage: expectedPhysical,
            mentalAverage: mentalLevel
        )
        if predictedPos > 96 {
            let excess = predictedPos - 96
            athleticism += excess
            expectedPhysical += excess
            mentalLevel += excess
        } else if predictedPos < 30 {
            let deficit = 30 - predictedPos
            athleticism -= deficit
            expectedPhysical -= deficit
            mentalLevel -= deficit
        }
        if expectedPhysical > 97 { athleticism -= expectedPhysical - 97 }
        if expectedPhysical < 30 { athleticism += 30 - expectedPhysical }
        mentalLevel = min(96, max(28, mentalLevel))

        let physical = PositionPhysicalProfile.sample(
            for: position,
            levelShift: athleticism - PositionPhysicalProfile.baseLevel,
            spread: 0.85
        )
        let mental = PositionPhysicalProfile.sampleMental(
            for: position,
            targetAverage: mentalLevel,
            spread: 0.85
        )

        predictedPos = solvePositionAverage(
            target: target,
            physicalAverage: physical.average,
            mentalAverage: mental.average
        )
        let positionAverage = min(97.0, max(25.0, predictedPos))

        let positionAttributes = buildPositionSkills(
            position: position,
            average: positionAverage,
            slot: slot,
            band: band,
            archetype: archetype,
            physical: physical,
            mental: mental,
            target: target,
            forceEliteTrait: forceEliteTrait
        )

        // Personality is drawn before the mental-software ratings because
        // competitiveness reads its archetype (plan §2.1).
        let personalityArchetype = PersonalityArchetype.allCases.randomElement()!

        // --- Step 6: learning (r ≈ 0.6 with awareness) ------------------------
        // The 0.40/0.60 blend that measured r ≈ 0.62 here now lives in
        // `MentalAttributeModel` (phase-2 plan §2.2) so `LeagueGenerator`'s
        // veterans and the legacy backfill draw from the same distribution.
        let learning = MentalAttributeModel.learning(
            awareness: mental.awareness,
            level: mentalLevel,
            shift: archetype.learningShift + learningPositionShift(for: position)
        )

        // --- Step 6b: competitiveness (plan §2.1) ------------------------------
        // Work ethic + clutch + personality tilt + an independent draw around
        // the prospect's own mental core, so two identically-graded prospects
        // can still answer a bad rookie year differently.
        let competitiveness = MentalAttributeModel.competitiveness(
            archetype: personalityArchetype,
            workEthic: mental.workEthic,
            clutch: mental.clutch
        )

        // --- Step 5: potential correlated with slot, overlapping ---------------
        let overall = Int(CollegeProspect.overallValue(
            position: positionAttributes, physical: physical, mental: mental
        ).rounded())
        let upside = drawUpside(position: position, age: age, band: band, archetype: archetype)
        let potential = min(99, max(overall, overall + Int(upside.rounded())))

        // --- Body ------------------------------------------------------------
        let hw = PositionPhysicalProfile.heightWeightRange(for: position)
        let name = RandomNameGenerator.uniqueName(used: &usedNames)
        let personality = PlayerPersonality(
            archetype: personalityArchetype,
            motivation: Motivation.allCases.randomElement()!
        )

        let prospect = CollegeProspect(
            firstName: name.first,
            lastName: name.last,
            college: ScoutingEngine.colleges.randomElement()!,
            position: position,
            age: age,
            height: Int.random(in: hw.height),
            weight: Int.random(in: hw.weight),
            truePhysical: physical,
            trueMental: mental,
            truePositionAttributes: positionAttributes,
            truePersonality: personality,
            truePotential: potential
        )

        // TODO §6 (#58): prospects carry a hometown from day one, so the
        // FA-drama hometown storylines keep firing as the generated-veteran
        // cohort retires out of the league.
        let hometown = HometownGenerator.randomHometown()
        prospect.hometownState = hometown.state
        prospect.hometownCity = hometown.city

        let anthro = ScoutingEngine.generateAnthropometrics(for: position)
        prospect.handSize = anthro.handSize
        prospect.armLength = anthro.armLength
        prospect.wingspan = anthro.wingspan

        prospect.trueLearning = learning
        prospect.trueCompetitiveness = competitiveness
        prospect.developmentArchetypeRaw = archetype.storedValue
        prospect.generatorVersion = currentGeneratorVersion

        // --- Step 9: provisional round projection ------------------------------
        // The TRUE grade band, which is what the class blueprint says this slot
        // is worth. `assignConsensusProjections` overwrites it a moment later
        // with the PUBLIC board — the market's read, error and all. This line
        // survives so a prospect built outside `buildOrdered` (a preview, a
        // one-off) still carries a sane projection.
        prospect.draftProjection = min(7, band)

        // --- Step 7: college production ---------------------------------------
        applyCollegeProduction(
            to: prospect,
            slot: slot,
            archetype: archetype,
            learning: learning,
            overall: overall
        )

        // --- Step 8: NFL readiness --------------------------------------------
        prospect.nflReadiness = nflReadiness(
            position: position,
            yearsStarted: prospect.collegeYearsStartedStored,
            age: age,
            learning: learning,
            archetype: archetype
        )

        var mutable = prospect
        ScoutingEngine.generateRiskProfile(for: &mutable)

        return prospect
    }

    /// `posAvg = (T − 0.3·physAvg − 0.2·mentalAvg) / 0.5` — the inverse of
    /// `Player.overall`, which `CollegeProspect.trueOverall` now mirrors.
    private static func solvePositionAverage(
        target: Double,
        physicalAverage: Double,
        mentalAverage: Double
    ) -> Double {
        (target - 0.3 * physicalAverage - 0.2 * mentalAverage) / 0.5
    }

    // MARK: - Step 4: position skills

    private static func buildPositionSkills(
        position: Position,
        average: Double,
        slot: Int,
        band: Int,
        archetype: Archetype,
        physical: PhysicalAttributes,
        mental: MentalAttributes,
        target: Double,
        forceEliteTrait: Bool = false
    ) -> PositionAttributes {
        let mask = techniqueMask(for: position)
        let count = mask.count
        var values = [Double](repeating: average, count: count)

        // Archetype tilt: polished prospects carry more of their grade in
        // technique skills, raw prospects in the explosive ones.
        for i in 0..<count {
            values[i] += mask[i] * archetype.techniqueTilt + Double.random(in: -8...8)
        }

        // Slot-banded ceiling on individual skills. A- / A / A+ position grades
        // (85+) must stay scarce, so only the top of the board may spike.
        var locked = Set<Int>()
        let cap = max(average + 3.0, skillCap(slot: slot))
        for i in 0..<count { values[i] = min(values[i], cap) }

        // Elite-trait rule: the top of the board gets 1–3 marquee skills.
        let keys = keySkillIndices(for: position).shuffled()
        if slot <= 12 {
            for i in keys.prefix(Int.random(in: 1...min(3, keys.count))) {
                values[i] = max(values[i], Double.random(in: 88...97))
                locked.insert(i)
            }
        } else if slot <= 40 {
            for i in keys.prefix(Int.random(in: 1...min(2, keys.count))) {
                values[i] = max(values[i], Double.random(in: 84...92))
                locked.insert(i)
            }
        } else if band >= 4, Double.random(in: 0...1) < 0.05, let i = keys.first {
            // Day-3 "freak trait": one standout skill on an otherwise late profile.
            values[i] = max(values[i], Double.random(in: 85...90))
            locked.insert(i)
        }

        // The best prospect at a premium position always has one A-range trait,
        // whichever slot he ended up in (plan §7.5).
        if forceEliteTrait, let i = keys.first {
            values[i] = max(values[i], Double.random(in: 88...94))
            locked.insert(i)
        }

        rebalance(&values, toAverage: average, locked: locked)

        var ints = values.map { PositionPhysicalProfile.clampInt($0, 25...99) }

        // Final polish: land `trueOverall` on the talent target (±1).
        let desired = Int(target.rounded())
        for _ in 0..<8 {
            let attrs = makePositionAttributes(position, values: ints)
            let current = CollegeProspect.overallValue(
                position: attrs, physical: physical, mental: mental
            )
            let delta = Double(desired) - current
            if abs(delta) < 0.5 { break }
            // d(overall)/d(one skill) = 0.5 / count
            let step = delta * Double(count) / 0.5
            let adjustable = (0..<count).filter { !locked.contains($0) }
            guard !adjustable.isEmpty else { break }
            let per = step / Double(adjustable.count)
            var changed = false
            for i in adjustable {
                let next = min(99, max(25, Int((Double(ints[i]) + per).rounded())))
                if next != ints[i] { ints[i] = next; changed = true }
            }
            if !changed { break }
        }

        return makePositionAttributes(position, values: ints)
    }

    /// Shifts the unlocked entries so the whole array averages `average`.
    private static func rebalance(_ values: inout [Double], toAverage average: Double, locked: Set<Int>) {
        let count = values.count
        guard count > 0 else { return }
        for _ in 0..<6 {
            let current = values.reduce(0, +) / Double(count)
            let delta = average - current
            if abs(delta) < 0.25 { return }
            let adjustable = (0..<count).filter { !locked.contains($0) }
            guard !adjustable.isEmpty else { return }
            let per = delta * Double(count) / Double(adjustable.count)
            for i in adjustable {
                values[i] = min(99, max(25, values[i] + per))
            }
        }
    }

    /// Ceiling for an individual position skill by board slot (plan §2 step 4).
    private static func skillCap(slot: Int) -> Double {
        switch slot {
        case ...12:  return Double.random(in: 88...97)
        case ...40:  return Double.random(in: 84...92)
        case ...115: return Double.random(in: 80...88)
        default:     return Double.random(in: 70...84)
        }
    }

    // MARK: - Step 5: the remaining-runway ceiling (task #32)

    /// How much of a prospect's remaining runway the board says he has NOT yet
    /// shown — the *projection* in his grade.
    ///
    /// This is the draft-board analogue of `LeagueGenerator.tierEarnedUpside`'s
    /// depth tier, but it is deliberately NOT monotonic in the band, because
    /// scouting is not:
    ///
    ///  * **Round 1 is the tier scouts can already SEE.** It is where the
    ///    polished, four-year-starting, pro-ready player goes — he grades there
    ///    *because* he has already converted his runway into technique. He has
    ///    the highest ceiling on the board (his true grade is 6-9 points above
    ///    Day 2's) and the least left to project.
    ///  * **Rounds 2-3 are the projection tier** — the traits-and-flashes
    ///    athlete, the one-year starter, the small-school riser. This is where a
    ///    club is explicitly buying what a player is not yet.
    ///  * **Rounds 4-7 and UDFA are the limited tier.** A late grade is a
    ///    statement that scouts see a role, not a runway.
    ///
    /// The curve is calibrated against the ONE external anchor the game has for
    /// this: `DRAFT_NFL_REFERENCE.md` §6's primary-starter hit rates by round
    /// (R1 ~60 % · R2 45 % · R3 33 % · R4 25 % · R5 18 % · R6 12 % · R7 10 % ·
    /// UDFA 4 %) and its elite shares, both asserted end-to-end by
    /// `tools/balance-harness`'s `career` scenario (6.1a-b, 6.2a-c). A monotone
    /// profile cannot hit that curve at a class mean potential the league can
    /// absorb: measured over the whole sweep, a flat cut deep enough to stop the
    /// ratchet (class mean 75.2) drops R2 to 29.7 % and R3 to 17.7 %, i.e.
    /// 15 pp under the reference, while a monotone profile generous enough to
    /// hold R2/R3 puts the class mean back at ~80 and the ratchet with it. The
    /// hump does both — see the table on `drawUpside`.
    static func bandProjection(band: Int) -> Double {
        switch band {
        case 1:  return 1.42
        case 2:  return 1.95
        case 3:  return 2.05
        case 4:  return 1.20
        case 5:  return 0.95
        case 6:  return 0.72
        case 7:  return 0.56
        default: return 0.38
        }
    }

    /// Remaining upside over `trueOverall`, drawn on the SAME model
    /// `LeagueGenerator.veteranPotential` uses for a young generated player:
    /// `runway = min(12, 2.5 · yearsToPeakWindow)`, scaled by what the board is
    /// still projecting, drawn at `N(0.55·μ, 0.8·μ)` and clipped at zero.
    ///
    /// ## Why this replaced the flat per-band mean (task #32)
    ///
    /// The old model was `N(bandUpsideMean, 5)` with `bandUpsideMean` 14 → 6 by
    /// band, plus an archetype shift and an age shift. Measured over 200 classes
    /// it produced band mean POTENTIALS of R1 95.2 · R2 89.1 · R3 84.2 · R4 80.3
    /// · R5 78.7 · R6 76.3 · R7 74.0 — a drafted-board mean of **81.1** against a
    /// league whose own mean potential is **75.0** (`leaguegen`, assert 8.hea:
    /// mean headroom over OVR 2.11). Every spring replaced ~15 % of the league
    /// with men carrying ~6 more points of ceiling than the men they displaced,
    /// so `MultiSeasonSmokeTest`'s `diag cohorts leaguePot` marched
    /// 75.0 → 77.4 → 78.8 → 79.6 and the §8 quality pyramid rose with it
    /// (80+ 17.8 % → 24.3 %, 90+ to 3.3 %) with no development constant touched.
    ///
    /// The two generators were describing different leagues. `LeagueGenerator`
    /// was corrected first (see its `veteranPotential` note — "the upside is now
    /// EARNED, not granted"), and this is the same correction applied to the
    /// other end of the same pipeline, in the same terms:
    ///
    ///  * **Age is the runway, not a ±3 shift.** A 20-year-old edge rusher is
    ///    six years from his peak window and a 23-year-old back is one; the old
    ///    `ageShift` compressed that into ±3 on top of a band constant that
    ///    already dominated it. `min(12, 2.5·yearsToWindow)` is
    ///    `LeagueGenerator`'s own runway, verbatim.
    ///  * **The draft grade supplies the scaler** (`bandProjection`) the way the
    ///    depth chart supplies it for a generated veteran.
    ///  * **The draw is centred at 0.55·runway with sd 0.8·μ and clipped at 0**,
    ///    so a real share of the board comes out with no headroom at all — the
    ///    polished, pro-ready senior who is what he is. `LeagueGenerator` puts
    ///    ~1 in 3 generated players there; the board is younger, so fewer.
    ///
    /// ## The sweep this landed from
    ///
    /// `runwayCentre` was swept with a MONOTONE profile (`career` harness, 20
    /// leagues × 30 seasons; `class` is the drafted-board mean potential):
    ///
    /// | profile | class | R2 hit | R3 hit | 80+ | 75+ | asserts |
    /// |---|---|---|---|---|---|---|
    /// | old (pre-wave) | 81.1 | 45.6 | 30.1 | 16.9 | 29.6 | 26/26 |
    /// | monotone ×0.55 | 75.2 | 29.7 | 17.7 | 11.6 | 22.8 | 20/26 |
    /// | monotone ×0.90 | 77.4 | 37.2 | 21.5 | 14.2 | 26.2 | 22/26 |
    /// | monotone ×1.15 | 78.6 | 40.9 | 23.6 | 15.8 | 28.4 | 25/26 |
    /// | monotone ×1.40 | 79.6 | 44.9 | 26.9 | 17.5 | 30.7 | 26/26 |
    ///
    /// i.e. a monotone profile trades the ratchet against the reference curve
    /// one-for-one and never fixes both. The hump breaks that trade because
    /// rounds 2-3 are only 24 % of the graded board: buying back the 9 points of
    /// R2/R3 ceiling that §6 needs costs the class mean just 1.2 points.
    ///
    /// **Shipped result** (`./run.sh draftclass`, 200 classes — band mean
    /// potential, and `./run.sh career`, 26/26):
    ///
    /// | | R1 | R2 | R3 | R4 | R5 | R6 | R7 | UDFA | class |
    /// |---|---|---|---|---|---|---|---|---|---|
    /// | old | 95.2 | 89.1 | 84.2 | 80.3 | 78.7 | 76.3 | 74.0 | 70.4 | **81.1** |
    /// | new | 90.5 | 86.9 | 84.7 | 78.2 | 75.3 | 72.5 | 69.2 | 65.7 | **78.0** |
    ///
    /// The tail is intact — R1/R2/R3 still draw p95 upsides of 17/23/25 onto an
    /// 83/77/74 true grade, so the top of every class still lands on the 99
    /// clamp and `career` measures R1 elite (peak OVR 90+) at 11.0 % against its
    /// 10-18 % band. What narrows is the middle and the back: a sixth-rounder's
    /// ceiling is now 4 points over his college grade rather than 8.
    ///
    /// `DraftEngine.rawnessPivot` moves 76 → 69 in the same wave so the rookie
    /// ENTRY level is unchanged — see the derivation there.
    static func drawUpside(
        position: Position,
        age: Int,
        band: Int,
        archetype: Archetype
    ) -> Double {
        let peak = position.peakAgeRange
        let runway = min(12.0, 2.5 * Double(max(0, peak.lowerBound - age)))
        let mu = runwayCentre * runway * bandProjection(band: band) * archetype.upsideMultiplier
        guard mu > 0 else { return 0 }
        let draw = PositionPhysicalProfile.gaussian(mean: mu, sd: max(1.0, mu * 0.8))
        return min(26.0, max(0.0, draw))
    }

    /// Where the runway draw is centred, as a fraction of the runway itself —
    /// `LeagueGenerator.veteranPotential`'s own constant, kept verbatim so the
    /// two ends of the pipeline share one model. All board-specific calibration
    /// lives in `bandProjection`.
    static let runwayCentre = 0.55

    // MARK: - Step 7: college production

    private static func applyCollegeProduction(
        to prospect: CollegeProspect,
        slot: Int,
        archetype: Archetype,
        learning: Int,
        overall: Int
    ) {
        // Competition level: 74 % P5 / 20 % G5 / 6 % FCS, early slots skew P5 —
        // an FCS prospect near the top of the board is the "small-school riser".
        // Drawn before the usage branch because a buried prospect is buried
        // somewhere, and the school is the flavour on the burial reason.
        let roll = Double.random(in: 0...1)
        let p5Bias = slot <= 60 ? 0.16 : 0.0
        let level: CollegeProspect.CollegeCompetitionLevel
        if roll < 0.74 + p5Bias {
            level = .powerFive
        } else if roll < 0.94 + p5Bias * 0.5 {
            level = .groupOfFive
        } else {
            level = .fcs
        }
        prospect.collegeCompetitionLevelRaw = level.rawValue

        // --- The buried branch (task #181) -----------------------------------
        if drawsBuriedUsage(position: prospect.position, age: prospect.age, archetype: archetype) {
            applyBuriedUsage(to: prospect, level: level)
            return
        }

        // Years started: polished / older prospects have more starts on tape.
        var years = max(1, min(4, prospect.age - 19 + archetype.yearsStartedShift))
        if Double.random(in: 0...1) < 0.15 { years = max(1, min(4, years + (Bool.random() ? 1 : -1))) }
        prospect.collegeYearsStartedStored = years

        let compBonus: Double
        switch level {
        case .powerFive:   compBonus = 0
        case .groupOfFive: compBonus = 3
        case .fcs:         compBonus = 5
        }

        // Calibration deviation: the plan's literal coefficients
        // (0.55·overall + 0.12·learning + …) top out around 63, which makes the
        // Elite/Above-Average tiers unreachable. Coefficients rescaled so the
        // score spans the tier table while keeping corr(score, trueOverall)
        // inside the 0.45–0.75 target band.
        let raw = 1.10 * Double(overall)
            + 0.12 * Double(learning)
            + 0.08 * Double(years) * 6.0
            + compBonus
            - 15.0
            + PositionPhysicalProfile.gaussian(mean: 0, sd: 7)
        let score = PositionPhysicalProfile.clampInt(raw, 20...99)
        prospect.collegeProductionScore = score

        let tier = CollegeProspect.productionTier(forScore: score)
        prospect.collegeProductionTierStored = tier.rawValue
        prospect.collegeStatLineStored = CollegeProspect.statLine(
            position: prospect.position,
            tier: tier,
            yearsStarted: years,
            seed: CollegeProspect.productionSeed(prospect.id)
        )
    }

    // MARK: - Step 7b: usage suppression / hidden gems (task #181)
    //
    // Before this, `collegeProductionScore` was a monotone function of
    // `trueOverall` plus σ = 7 of noise, so the production column and the
    // hidden grade were the same statement made twice. A user who learned to
    // read the tier chip had a free, unfogged, always-correct estimate of a
    // number the entire scouting economy exists to charge him for.
    //
    // The fix is not more noise — noise is symmetric and forgettable. It is a
    // SECOND CAUSE for a low production number: a small slice of every class
    // never got on the field at all, and for those men production measures
    // USAGE and nothing else. Most of them are exactly what they look like.
    // A real minority are not, and finding them is a scouting decision with a
    // reason behind it rather than a coin flip.
    //
    // The cohort's ability distribution is deliberately NOT re-drawn: the
    // burial roll is independent of the talent backbone, so the buried slice
    // inherits the class pyramid — mostly middling players, roughly one
    // first-round talent per class. That is the mix the design asked for and it
    // falls out of independence rather than out of a tuned table.

    /// Whether this prospect's college career is a usage story rather than a
    /// production story.
    ///
    /// Gated on underclassmen: a 22-year-old with no starts behind him is a
    /// career backup, not a man who has not had his turn yet, and putting him
    /// in the cohort would fill it with prospects for whom the low grade is
    /// simply correct. Specialists are excluded — a kicker is not buried on a
    /// depth chart, he is the kicker or he is not on the team.
    ///
    /// The per-archetype rates run against `yearsStartedShift`: a polished
    /// prospect is polished BECAUSE he has played, so he is the least likely to
    /// have sat. Class share works out at ≈ 4–6 % (measured; see the
    /// `draftclass` gate §7.9c).
    static func drawsBuriedUsage(position: Position, age: Int, archetype: Archetype) -> Bool {
        guard position != .K, position != .P else { return false }
        guard age < CollegeProspect.seniorAge else { return false }
        let rate: Double
        switch archetype {
        case .polished: rate = 0.03
        case .balanced: rate = 0.09
        case .raw:      rate = 0.13
        }
        return Double.random(in: 0...1) < rate
    }

    /// Writes the buried prospect's production record: snaps instead of a
    /// season, a score derived from those snaps, and the narrative hook that
    /// keeps "89 snaps" from reading as "bad player" with no further comment.
    private static func applyBuriedUsage(
        to prospect: CollegeProspect,
        level: CollegeProspect.CollegeCompetitionLevel
    ) {
        // 0 or 1 starts — a spot start when the man ahead tweaked a hamstring
        // is the most tape any of these prospects has.
        let starts = Double.random(in: 0...1) < 0.55 ? 0 : 1
        prospect.collegeYearsStartedStored = starts

        let snaps = PositionPhysicalProfile.clampInt(
            PositionPhysicalProfile.gaussian(mean: 120, sd: 45),
            35...240
        )
        prospect.collegeSnapsPlayed = snaps
        prospect.collegeBurialReason = burialReason(level: level, starts: starts)

        // PRODUCTION FROM USAGE, NOT FROM ABILITY. This is the whole mechanic:
        // the score the public board reads is a function of how much he played
        // and of nothing else, so `corr(production, trueOverall)` over this
        // slice is ~0 by construction. Span 20…66 keeps a buried man inside
        // Below Avg / low Average, which is what an unproductive season looks
        // like on a chip.
        let raw = 24.0
            + 30.0 * Double(snaps - 35) / 205.0
            + Double(starts) * 4.0
            + PositionPhysicalProfile.gaussian(mean: 0, sd: 3)
        let score = PositionPhysicalProfile.clampInt(raw, 20...66)
        prospect.collegeProductionScore = score

        let tier = CollegeProspect.productionTier(forScore: score)
        prospect.collegeProductionTierStored = tier.rawValue
        prospect.collegeStatLineStored = CollegeProspect.statLine(
            position: prospect.position,
            tier: tier,
            yearsStarted: starts,
            seed: CollegeProspect.productionSeed(prospect.id),
            limitedSampleSnaps: snaps
        )
    }

    /// English-only, one line, written as the scouting-report sentence a board
    /// row can quote verbatim.
    private static func burialReason(
        level: CollegeProspect.CollegeCompetitionLevel,
        starts: Int
    ) -> String {
        var pool = [
            "sat behind a first-round pick",
            "buried on a loaded depth chart",
            "lost the job in fall camp and never got it back",
            "transferred in and sat out a season",
            "redshirted, then lost a year to injury",
            "stuck behind a fifth-year senior",
            "played special teams only",
        ]
        if starts > 0 {
            pool.append("one spot start, then back to the bench")
        }
        if level == .powerFive {
            pool.append("four-star recruit who never won the job")
        }
        return pool.randomElement() ?? pool[0]
    }

    // MARK: - Step 8: NFL readiness

    private static func nflReadiness(
        position: Position,
        yearsStarted: Int,
        age: Int,
        learning: Int,
        archetype: Archetype
    ) -> Int {
        let positionShift: Double
        switch position {
        case .RB, .FB, .CB, .LT, .RT:   positionShift = 6
        case .WR, .DE, .DT, .LG, .RG:   positionShift = 0
        case .OLB, .MLB, .FS, .SS, .TE: positionShift = -4
        case .QB, .C:                   positionShift = -8
        case .K, .P:                    positionShift = 0
        }
        let raw = 35.0
            + Double(yearsStarted) * 9.0
            + Double(age - 20) * 4.0
            + Double(learning) * 0.15
            + archetype.readinessShift
            + positionShift
            + PositionPhysicalProfile.gaussian(mean: 0, sd: 6)
        return PositionPhysicalProfile.clampInt(raw, 25...95)
    }

    // MARK: - Step 3: archetype

    enum Archetype {
        case polished, balanced, raw

        var storedValue: String {
            switch self {
            case .polished: return CollegeProspect.DevelopmentArchetype.polished.rawValue
            case .balanced: return CollegeProspect.DevelopmentArchetype.balanced.rawValue
            case .raw:      return CollegeProspect.DevelopmentArchetype.raw.rawValue
            }
        }

        /// Raw prospects carry more of their grade in the body, polished in technique.
        var physicalTilt: Double {
            switch self {
            case .polished: return -2
            case .balanced: return 0
            case .raw:      return 3
            }
        }

        var mentalTilt: Double {
            switch self {
            case .polished: return 4
            case .balanced: return 0
            case .raw:      return -4
            }
        }

        var techniqueTilt: Double {
            switch self {
            case .polished: return 3
            case .balanced: return 0
            case .raw:      return -3
            }
        }

        /// Multiplier on the remaining-runway draw (`drawUpside`). A raw prospect
        /// is further from the player he will be, a polished one is closer —
        /// which is a statement about the SIZE of his runway, not a fixed ±4 on
        /// top of it. Scale-free by construction, so it survives any future
        /// recalibration of the runway itself.
        var upsideMultiplier: Double {
            switch self {
            case .polished: return 0.75
            case .balanced: return 1.00
            case .raw:      return 1.30
            }
        }

        var readinessShift: Double {
            switch self {
            case .polished: return 8
            case .balanced: return 0
            case .raw:      return -8
            }
        }

        var learningShift: Double {
            switch self {
            case .polished: return 3
            case .balanced: return 0
            case .raw:      return -3
            }
        }

        var yearsStartedShift: Int {
            switch self {
            case .polished: return 1
            case .balanced: return 0
            case .raw:      return -1
            }
        }
    }

    /// Polished 25 % / Balanced 55 % / Raw 20 %, biased by position:
    /// QB and offensive line skew polished, WR / DB / EDGE skew raw.
    private static func drawArchetype(for position: Position) -> Archetype {
        var polished = 0.25
        var rawShare = 0.20
        switch position {
        case .QB, .LT, .LG, .C, .RG, .RT:
            polished += 0.10; rawShare -= 0.06
        case .WR, .CB, .FS, .SS, .DE:
            polished -= 0.08; rawShare += 0.10
        case .K, .P:
            polished += 0.05; rawShare -= 0.05
        default:
            break
        }
        let roll = Double.random(in: 0...1)
        if roll < polished { return .polished }
        if roll < polished + (1.0 - polished - rawShare) { return .balanced }
        return .raw
    }

    private static func drawAge(archetype: Archetype) -> Int {
        switch archetype {
        case .polished:
            return Double.random(in: 0...1) < 0.65 ? Int.random(in: 22...23) : Int.random(in: 20...21)
        case .balanced:
            return Int.random(in: 20...23)
        case .raw:
            return Double.random(in: 0...1) < 0.65 ? Int.random(in: 20...21) : Int.random(in: 22...23)
        }
    }

    private static func learningPositionShift(for position: Position) -> Double {
        switch position {
        case .QB, .C, .MLB, .FS, .SS: return 3
        case .RB, .FB, .K, .P:        return -2
        default:                      return 0
        }
    }

    // MARK: - Position groups

    /// Draft-board position groups. Counts and round-band shares are defined at
    /// group level (that is how the NFL reference reports them) and split across
    /// member positions afterwards.
    enum PositionGroup: String, CaseIterable {
        case qb, rb, fb, wr, te, ot, iol, edge, dt, lb, cb, safety, kicker, punter

        /// Members with their relative weight inside the group.
        var memberWeights: [(Position, Double)] {
            switch self {
            case .qb:     return [(.QB, 1.0)]
            case .rb:     return [(.RB, 1.0)]
            case .fb:     return [(.FB, 1.0)]
            case .wr:     return [(.WR, 1.0)]
            case .te:     return [(.TE, 1.0)]
            case .ot:     return [(.LT, 0.5), (.RT, 0.5)]
            case .iol:    return [(.LG, 1.0 / 3.0), (.C, 1.0 / 3.0), (.RG, 1.0 / 3.0)]
            case .edge:   return [(.DE, 0.573), (.OLB, 0.427)]
            case .dt:     return [(.DT, 1.0)]
            case .lb:     return [(.MLB, 1.0)]
            case .cb:     return [(.CB, 1.0)]
            case .safety: return [(.FS, 0.514), (.SS, 0.486)]
            case .kicker: return [(.K, 1.0)]
            case .punter: return [(.P, 1.0)]
            }
        }

        var members: [Position] { memberWeights.map { $0.0 } }

        /// Share of the whole class (plan §4).
        var classShare: Double {
            switch self {
            case .qb:     return 5.5
            case .rb:     return 8.7
            case .fb:     return 0.9
            case .wr:     return 14.0
            case .te:     return 6.0
            case .ot:     return 6.4
            case .iol:    return 7.8
            case .edge:   return 13.1
            case .dt:     return 7.5
            case .lb:     return 4.1
            case .cb:     return 13.1
            case .safety: return 7.0
            case .kicker: return 0.9
            case .punter: return 0.9
            }
        }

        /// Observed per-class count range for a 350-man class (plan §4).
        var classCountRange: ClosedRange<Int> {
            switch self {
            case .qb:     return 12...24
            case .rb:     return 22...36
            case .fb:     return 2...5
            case .wr:     return 36...56
            case .te:     return 14...26
            case .ot:     return 16...30
            case .iol:    return 18...30
            case .edge:   return 30...48
            case .dt:     return 18...32
            case .lb:     return 9...20
            case .cb:     return 32...52
            case .safety: return 15...28
            case .kicker: return 3...6
            case .punter: return 3...6
            }
        }

        /// Share of the non-QB first-round grades (plan §4). QB is drawn from
        /// its own histogram instead.
        var firstRoundShare: Double {
            switch self {
            case .qb:     return 0
            // rb/safety carry a premium over their plan-§4 shares: the non-QB R1
            // pool (~24.3 grades) runs ~8 % below the NFL pick-based references
            // and largest-remainder rounding drags small shares hardest, so the
            // raw values are set to land the REALIZED means on the reference
            // (rb 1.4, safety 1.2) — measured over 200-class harness runs.
            case .rb:     return 5.1
            case .wr:     return 13
            case .te:     return 3.5
            case .ot:     return 14
            case .iol:    return 7
            case .edge:   return 15
            case .dt:     return 9
            case .lb:     return 2
            case .cb:     return 14
            case .safety: return 4.3
            case .fb, .kicker, .punter: return 0
            }
        }

        var firstRoundRange: ClosedRange<Int> {
            switch self {
            case .qb:     return 1...6
            case .rb:     return 0...3
            case .wr:     return 2...7
            case .te:     return 0...2
            case .ot:     return 2...7
            case .iol:    return 0...4
            case .edge:   return 2...7
            case .dt:     return 1...6
            case .lb:     return 0...2
            case .cb:     return 2...7
            case .safety: return 0...3
            case .fb, .kicker, .punter: return 0...0
            }
        }

        /// Share of the group's drafted players landing on day 2 (R2–3) and
        /// day 3 (R4–7) — `DRAFT_NFL_REFERENCE.md` §3.
        var roundSkew: (day2: Double, day3: Double) {
            switch self {
            case .qb:     return (0.22, 0.50)
            case .rb:     return (0.26, 0.67)
            case .fb:     return (0.10, 0.70)
            case .wr:     return (0.30, 0.57)
            case .te:     return (0.27, 0.66)
            case .ot:     return (0.30, 0.45)
            case .iol:    return (0.30, 0.58)
            case .edge:   return (0.30, 0.50)
            case .dt:     return (0.28, 0.54)
            case .lb:     return (0.30, 0.60)
            case .cb:     return (0.30, 0.55)
            case .safety: return (0.30, 0.62)
            case .kicker, .punter: return (0.04, 0.96)
            }
        }

        /// The best prospect of this group may never grade worse than this band
        /// (`DRAFT_NFL_REFERENCE.md` §4). `nil` = no guarantee.
        var bestProspectBandGuarantee: Int? {
            switch self {
            case .qb, .wr, .ot, .edge, .cb, .dt: return 1
            case .rb, .safety, .te, .lb, .iol:   return 2
            default:                             return nil
            }
        }

        /// Earliest band this group may occupy. Kickers and punters have never
        /// gone before round 4 in the modern draft.
        var earliestBand: Int {
            switch self {
            case .kicker, .punter: return 4
            case .fb:              return 4
            default:               return 1
            }
        }

        /// QB / TE classes swing hardest year to year (reference §9).
        var strengthSigma: Double {
            switch self {
            case .qb, .te: return 0.18
            default:       return 0.15
            }
        }
    }

    // MARK: - Step 1: blueprint

    private static func drawGroupStrengths() -> [PositionGroup: Double] {
        var result: [PositionGroup: Double] = [:]
        for group in PositionGroup.allCases {
            let draw = PositionPhysicalProfile.gaussian(mean: 1.0, sd: group.strengthSigma)
            result[group] = min(1.35, max(0.70, draw))
        }
        return result
    }

    /// Class-size scaled band capacities: R1 … R7 then UDFA (index 0 = R1).
    private static func bandSizes(for size: Int) -> [Int] {
        let scale = Double(size) / 350.0
        let r1 = max(6, Int((Double(Int.random(in: 26...30)) * scale).rounded()))
        let base = [33, 38, 43, 47, 51, 55]
        var sizes = [r1]
        for value in base {
            sizes.append(max(3, Int((Double(value) * scale).rounded())))
        }
        let assigned = sizes.reduce(0, +)
        sizes.append(max(0, size - assigned))
        // If rounding overshot the class size, trim from the back.
        var overflow = sizes.reduce(0, +) - size
        var index = sizes.count - 1
        while overflow > 0 && index >= 0 {
            let take = min(overflow, sizes[index])
            sizes[index] -= take
            overflow -= take
            index -= 1
        }
        return sizes
    }

    private static func allocateGroupCounts(
        size: Int,
        strengths: [PositionGroup: Double]
    ) -> [PositionGroup: Int] {
        let scale = Double(size) / 350.0
        var weights: [PositionGroup: Double] = [:]
        var totalWeight = 0.0
        for group in PositionGroup.allCases {
            let weight = group.classShare * (strengths[group] ?? 1.0)
            weights[group] = weight
            totalWeight += weight
        }

        // Proportional allocation with clamps, then largest remainder.
        //
        // Calibration note (balance-harness `draftclass`): the first cut floored
        // every quota and reconciled the rest by bumping a *random* group ±1.
        // Every group was equally likely to be picked regardless of size, so the
        // three-man groups (K, P, FB) absorbed the same absolute drift as the
        // fifty-man ones — measured +20 % on K/P/FB over 200 classes. Two things
        // fix that: whenever a group is pinned to a clamp, its surplus/shortfall
        // is redistributed *in proportion to the other groups' shares* (a group
        // holding 0.9 % of the class must not absorb the same slack as one
        // holding 14 %), and the final rounding units go to the largest
        // fractional parts instead of at random.
        var bounds: [PositionGroup: (lower: Int, upper: Int)] = [:]
        for group in PositionGroup.allCases {
            let range = group.classCountRange
            let lower = max(1, Int((Double(range.lowerBound) * scale).rounded()))
            let upper = max(lower, Int((Double(range.upperBound) * scale).rounded()))
            bounds[group] = (lower, upper)
        }

        var quota: [PositionGroup: Double] = [:]
        var pinned: [PositionGroup: Double] = [:]
        var active = Set(PositionGroup.allCases)
        var remainingSize = Double(size)
        var pinPass = 0
        while pinPass < PositionGroup.allCases.count {
            pinPass += 1
            let activeWeight = active.reduce(0.0) { $0 + (weights[$1] ?? 0) }
            guard activeWeight > 0 else { break }
            var newlyPinned = false
            for group in active {
                let raw = (weights[group] ?? 0) / activeWeight * remainingSize
                let bound = bounds[group] ?? (1, size)
                if raw < Double(bound.lower) {
                    pinned[group] = Double(bound.lower); newlyPinned = true
                } else if raw > Double(bound.upper) {
                    pinned[group] = Double(bound.upper); newlyPinned = true
                }
            }
            if newlyPinned {
                for (group, value) in pinned where active.contains(group) {
                    active.remove(group)
                    remainingSize -= value
                }
                continue
            }
            for group in active {
                quota[group] = (weights[group] ?? 0) / activeWeight * remainingSize
            }
            break
        }
        for (group, value) in pinned { quota[group] = value }

        var counts: [PositionGroup: Int] = [:]
        var remainder: [PositionGroup: Double] = [:]
        for group in PositionGroup.allCases {
            let raw = quota[group] ?? 0
            let bound = bounds[group] ?? (1, size)
            let floored = min(bound.upper, max(bound.lower, Int(raw.rounded(.down))))
            counts[group] = floored
            remainder[group] = raw - Double(floored)
        }

        var total = counts.values.reduce(0, +)
        var guardCounter = 0
        while total != size && guardCounter < 4000 {
            guardCounter += 1
            let needMore = total < size
            let candidates = PositionGroup.allCases.filter { group in
                guard let bound = bounds[group], let current = counts[group] else { return false }
                return needMore ? current < bound.upper : current > bound.lower
            }
            guard !candidates.isEmpty else { break }
            let pick = needMore
                ? candidates.max { (remainder[$0] ?? 0) < (remainder[$1] ?? 0) }!
                : candidates.min { (remainder[$0] ?? 0) < (remainder[$1] ?? 0) }!
            counts[pick, default: 0] += needMore ? 1 : -1
            remainder[pick, default: 0] += needMore ? -1 : 1
            total += needMore ? 1 : -1
        }
        return counts
    }

    /// QB first-round count, drawn from the smoothed 10-year histogram
    /// `{1: 8 %, 2: 18 %, 3: 26 %, 4: 22 %, 5: 16 %, 6: 10 %}`.
    private static func drawQBFirstRounders() -> Int {
        let roll = Double.random(in: 0...100)
        switch roll {
        case ..<8:   return 1
        case ..<26:  return 2
        case ..<52:  return 3
        case ..<74:  return 4
        case ..<90:  return 5
        default:     return 6
        }
    }

    private static func allocateFirstRound(
        capacity: Int,
        groupCounts: [PositionGroup: Int],
        strengths: [PositionGroup: Double]
    ) -> [PositionGroup: Int] {
        var counts: [PositionGroup: Int] = [:]
        let qb = min(max(1, drawQBFirstRounders()), min(capacity, groupCounts[.qb] ?? 1))
        counts[.qb] = qb

        let remaining = max(0, capacity - qb)
        let others = PositionGroup.allCases.filter { $0 != .qb && $0.firstRoundShare > 0 }
        let shareTotal = others.reduce(0.0) { $0 + $1.firstRoundShare * (strengths[$1] ?? 1.0) }

        for group in PositionGroup.allCases where group != .qb {
            guard group.firstRoundShare > 0, shareTotal > 0 else {
                counts[group] = 0
                continue
            }
            let raw = group.firstRoundShare * (strengths[group] ?? 1.0) / shareTotal * Double(remaining)
            let range = group.firstRoundRange
            let cap = min(range.upperBound, groupCounts[group] ?? 0)
            counts[group] = min(cap, max(min(range.lowerBound, cap), Int(raw.rounded())))
        }

        // Reconcile to the exact first-round capacity.
        var total = counts.values.reduce(0, +)
        var guardCounter = 0
        while total != capacity && guardCounter < 2000 {
            guardCounter += 1
            let needMore = total < capacity
            let candidates = PositionGroup.allCases.filter { group in
                let range = group.firstRoundRange
                let current = counts[group] ?? 0
                let cap = min(range.upperBound, groupCounts[group] ?? 0)
                if group == .qb {
                    // Never let the reconciliation break the QB histogram draw.
                    return false
                }
                return needMore ? current < cap : current > range.lowerBound
            }
            guard let pick = candidates.randomElement() else { break }
            counts[pick, default: 0] += needMore ? 1 : -1
            total += needMore ? 1 : -1
        }
        return counts
    }

    // MARK: - Slot tokens

    private struct SlotToken {
        var group: PositionGroup
        var position: Position
        var band: Int
        let desiredBand: Int
    }

    /// Exchanges *who* sits in two slots while leaving each slot's band intact —
    /// bands are a property of the board position, not of the prospect.
    private static func swapAssignments(_ tokens: inout [SlotToken], _ lhs: Int, _ rhs: Int) {
        let lhsGroup = tokens[lhs].group
        let lhsPosition = tokens[lhs].position
        tokens[lhs].group = tokens[rhs].group
        tokens[lhs].position = tokens[rhs].position
        tokens[rhs].group = lhsGroup
        tokens[rhs].position = lhsPosition
    }

    /// Builds the ordered slot list: every prospect gets a *desired* band from
    /// the positional round skew, tokens are then sorted and packed into the
    /// fixed band capacities so each band ends up exactly the right size.
    private static func buildSlotTokens(
        groupCounts: [PositionGroup: Int],
        r1Counts: [PositionGroup: Int],
        bandSizes: [Int]
    ) -> [SlotToken] {
        var tokens: [SlotToken] = []

        for group in PositionGroup.allCases {
            let total = groupCounts[group] ?? 0
            guard total > 0 else { continue }
            let firstRound = min(r1Counts[group] ?? 0, total)
            var positions = splitAcrossMembers(group: group, count: total)
            positions.shuffle()

            let skew = group.roundSkew
            let udfaWeight = 0.20
            // R2, R3 split the day-2 share; R4…R7 split the day-3 share.
            var weights = [skew.day2 / 2, skew.day2 / 2,
                           skew.day3 / 4, skew.day3 / 4, skew.day3 / 4, skew.day3 / 4,
                           udfaWeight]
            let earliest = group.earliestBand
            if earliest > 2 {
                for index in 0..<min(weights.count, earliest - 2) { weights[index] = 0 }
            }
            let weightTotal = max(0.0001, weights.reduce(0, +))

            for (index, position) in positions.enumerated() {
                let desired: Int
                if index < firstRound {
                    desired = 1
                } else {
                    var roll = Double.random(in: 0...weightTotal)
                    var chosen = weights.count - 1
                    for (offset, weight) in weights.enumerated() {
                        roll -= weight
                        if roll <= 0 { chosen = offset; break }
                    }
                    desired = max(earliest, chosen + 2)
                }
                tokens.append(SlotToken(group: group, position: position, band: desired, desiredBand: desired))
            }
        }

        // Pack into the fixed band capacities.
        tokens.sort { lhs, rhs in
            if lhs.desiredBand != rhs.desiredBand { return lhs.desiredBand < rhs.desiredBand }
            // Specialists sit at the back of any band they share.
            let lhsSpecial = lhs.group == .kicker || lhs.group == .punter || lhs.group == .fb
            let rhsSpecial = rhs.group == .kicker || rhs.group == .punter || rhs.group == .fb
            if lhsSpecial != rhsSpecial { return rhsSpecial }
            return Bool.random()
        }

        var slot = 0
        for (bandIndex, capacity) in bandSizes.enumerated() {
            let band = bandIndex + 1
            for _ in 0..<capacity where slot < tokens.count {
                tokens[slot].band = band
                slot += 1
            }
        }
        while slot < tokens.count {
            tokens[slot].band = bandSizes.count
            slot += 1
        }
        return tokens
    }

    private static func splitAcrossMembers(group: PositionGroup, count: Int) -> [Position] {
        let weights = group.memberWeights
        guard weights.count > 1 else {
            return Array(repeating: weights[0].0, count: count)
        }
        var result: [Position] = []
        var assigned = 0
        for (index, entry) in weights.enumerated() {
            let share: Int
            if index == weights.count - 1 {
                share = count - assigned
            } else {
                share = Int((Double(count) * entry.1).rounded())
            }
            let clamped = max(0, min(share, count - assigned))
            result.append(contentsOf: Array(repeating: entry.0, count: clamped))
            assigned += clamped
        }
        while result.count < count { result.append(weights[0].0) }
        return result
    }

    // MARK: - Hard invariants (plan §2 step 1.4)

    private static func enforceInvariants(tokens: inout [SlotToken]) {
        // 1. Kickers / punters / fullbacks never grade better than round 4.
        for index in tokens.indices where tokens[index].band < tokens[index].group.earliestBand {
            let earliest = tokens[index].group.earliestBand
            guard let swap = tokens.indices.last(where: {
                tokens[$0].band >= earliest && tokens[$0].group.earliestBand == 1
            }), swap > index else { continue }
            swapAssignments(&tokens, index, swap)
        }

        // 2. Best-at-position guarantees. Even in the weakest year, the top QB /
        //    WR / OT / EDGE / CB / DT is a first-round grade and the top RB / S /
        //    TE / LB / IOL is no worse than round 2.
        for group in PositionGroup.allCases {
            guard let guarantee = group.bestProspectBandGuarantee else { continue }
            let indices = tokens.indices.filter { tokens[$0].group == group }
            guard let best = indices.first else { continue }
            guard tokens[best].band > guarantee else { continue }
            // Swap with the latest token inside the guaranteed band whose own
            // group would not be left short.
            let candidate = tokens.indices.last { index in
                guard tokens[index].band <= guarantee else { return false }
                let other = tokens[index].group
                guard other != group, other.earliestBand == 1 else { return false }
                if let otherGuarantee = other.bestProspectBandGuarantee {
                    // Only give up a slot the other group can spare.
                    let otherCount = tokens.indices.filter {
                        tokens[$0].group == other && tokens[$0].band <= otherGuarantee
                    }.count
                    return otherCount > 1
                }
                return true
            }
            if let candidate, candidate < best {
                swapAssignments(&tokens, best, candidate)
            }
        }

        // 3. A class never carries more than 8 QBs with a top-two-round grade.
        var qbEarly = tokens.indices.filter { tokens[$0].group == .qb && tokens[$0].band <= 2 }
        var guardCounter = 0
        while qbEarly.count > 8, let demote = qbEarly.last, guardCounter < 32 {
            guardCounter += 1
            guard let target = tokens.indices.first(where: {
                tokens[$0].band >= 3 && tokens[$0].group != .qb && tokens[$0].group.earliestBand == 1
            }) else { break }
            swapAssignments(&tokens, demote, target)
            qbEarly = tokens.indices.filter { tokens[$0].group == .qb && tokens[$0].band <= 2 }
        }
    }

    /// Shuffles within each band so no positional blocks form on the board.
    private static func shuffleWithinBands(tokens: inout [SlotToken], bandSizes: [Int]) {
        var start = 0
        for capacity in bandSizes {
            let end = min(tokens.count, start + capacity)
            guard end > start else { break }
            var slice = Array(tokens[start..<end])
            slice.shuffle()
            tokens.replaceSubrange(start..<end, with: slice)
            start = end
        }
    }

    // MARK: - Position skill plumbing

    /// Positive = technique skill (polished prospects lead here),
    /// negative = explosive / traits skill (raw prospects lead here).
    private static func techniqueMask(for position: Position) -> [Double] {
        switch position {
        case .QB:
            // arm, short, mid, deep, pocket, scramble
            return [-1.0, 1.0, 1.0, 0.5, 1.0, -1.0]
        case .WR:
            // route, catch, release, spectacular
            return [1.0, 0.5, 1.0, -1.0]
        case .RB, .FB:
            // vision, elusiveness, breakTackle, receiving
            return [1.0, -0.5, -1.0, 0.5]
        case .TE:
            // blocking, catching, route, speed
            return [1.0, 0.0, 1.0, -1.0]
        case .LT, .LG, .C, .RG, .RT:
            // runBlock, passBlock, pull, anchor
            return [0.5, 1.0, -1.0, 0.0]
        case .DE, .DT:
            // passRush, blockShedding, power, finesse
            return [0.0, 0.5, -0.5, 1.0]
        case .OLB, .MLB:
            // tackling, zone, man, blitz
            return [0.0, 1.0, 0.5, -1.0]
        case .CB, .FS, .SS:
            // man, zone, press, ballSkills
            return [0.0, 1.0, 0.5, -1.0]
        case .K, .P:
            // power, accuracy
            return [-1.0, 1.0]
        }
    }

    /// Marquee skills that may spike into the A range for top-of-board prospects.
    private static func keySkillIndices(for position: Position) -> [Int] {
        switch position {
        case .QB:                       return [1, 2, 0]     // short / mid accuracy, arm
        case .WR:                       return [0, 1]        // route running, hands
        case .RB, .FB:                  return [0, 1]        // vision, elusiveness
        case .TE:                       return [1, 0]        // hands, blocking
        case .LT, .LG, .C, .RG, .RT:    return [1, 0]        // pass block, run block
        case .DE, .DT:                  return [0, 1]        // pass rush, block shed
        case .OLB, .MLB:                return [0, 1]        // tackling, zone
        case .CB, .FS, .SS:             return [0, 3]        // man coverage, ball skills
        case .K, .P:                    return [1, 0]        // accuracy, power
        }
    }

    private static func makePositionAttributes(_ position: Position, values: [Int]) -> PositionAttributes {
        func v(_ index: Int) -> Int { index < values.count ? values[index] : 60 }
        switch position {
        case .QB:
            return .quarterback(QBAttributes(
                armStrength: v(0), accuracyShort: v(1), accuracyMid: v(2),
                accuracyDeep: v(3), pocketPresence: v(4), scrambling: v(5)))
        case .WR:
            return .wideReceiver(WRAttributes(
                routeRunning: v(0), catching: v(1), release: v(2), spectacularCatch: v(3)))
        case .RB, .FB:
            return .runningBack(RBAttributes(
                vision: v(0), elusiveness: v(1), breakTackle: v(2), receiving: v(3)))
        case .TE:
            return .tightEnd(TEAttributes(
                blocking: v(0), catching: v(1), routeRunning: v(2), speed: v(3)))
        case .LT, .LG, .C, .RG, .RT:
            return .offensiveLine(OLAttributes(
                runBlock: v(0), passBlock: v(1), pull: v(2), anchor: v(3)))
        case .DE, .DT:
            return .defensiveLine(DLAttributes(
                passRush: v(0), blockShedding: v(1), powerMoves: v(2), finesseMoves: v(3)))
        case .OLB, .MLB:
            return .linebacker(LBAttributes(
                tackling: v(0), zoneCoverage: v(1), manCoverage: v(2), blitzing: v(3)))
        case .CB, .FS, .SS:
            return .defensiveBack(DBAttributes(
                manCoverage: v(0), zoneCoverage: v(1), press: v(2), ballSkills: v(3)))
        case .K, .P:
            return .kicking(KickingAttributes(kickPower: v(0), kickAccuracy: v(1)))
        }
    }
}
