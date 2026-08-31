import Foundation

// MARK: - Seeded RNG

/// SplitMix64 — the deterministic generator behind the fixed-league import.
///
/// Same algorithm the scouting pool already uses (`CoachingEngine`'s private
/// `ScoutPoolGenerator`), lifted to file scope because the template import needs
/// it across several types. SplitMix64 is specifically designed to be seeded
/// from a counter, so the `globalSeed + entityID` seeds used by
/// `LeagueTemplateImporter` decorrelate properly even when neighbouring seeds
/// differ by 1.
struct SeededLeagueRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Solver

/// Reconstructs a template player's attribute grid from his `ratingTarget`.
///
/// A baked league template (`LeagueTemplate`) does not carry attributes — it
/// carries the OVR the transform calibrated each player to, plus mean-zero
/// `areaHints` describing the SHAPE of his skill set. This solver turns that
/// pair back into the game's own `PhysicalAttributes` / `MentalAttributes` /
/// position skills, so an imported veteran is indistinguishable in structure
/// from a generated one.
///
/// ## Method
///
/// The caller supplies the three attribute levels the RANDOM generator would
/// use for this player's depth tier and age (`LeagueGenerator.veteranLevelShift`
/// + `ageLevelShift` + the tier's skill band). On top of those, the solver
/// bisects one uniform ability offset `d` — added identically to all three, so
/// the physical / mental / skill *split* stays exactly where the random league
/// puts it and only the LEVEL moves — until `Player.overall` lands on the
/// target. A final ±1 round-robin closes the last rounding point.
///
/// The draw is a pure function of `(seed, d)`: the same seed always rebuilds
/// the same player, which is what makes a template league constant across
/// imports.
///
/// Deliberately free of any `@Model` dependency (no `Player`, no SwiftData), so
/// it is pure math over `Position` + `PlayerAttributes` + the shared
/// `PositionPhysicalProfile` priors — the same discipline `MentalAttributeModel`
/// follows, and what lets the balance harness compile it standalone.
enum TemplateAttributeSolver {

    // MARK: - Inputs

    /// The three attribute levels a player is drawn around, before his
    /// individual ability offset.
    struct Levels {
        /// Centre of each position-skill draw (tier band midpoint + age shift).
        var skill: Double
        /// `levelShift` handed to `PositionPhysicalProfile.sample`.
        var physical: Double
        /// `targetAverage` handed to `PositionPhysicalProfile.sampleMental`.
        var mental: Double
    }

    /// A solved attribute grid.
    struct Solution {
        var physical: PhysicalAttributes
        var mental: MentalAttributes
        /// Position skills in `skillKeys(for:)` order.
        var skills: [Int]
        /// The same skills packed into the game's position-attribute enum.
        var positionAttributes: PositionAttributes
        /// `Player.overall` this grid produces. Equals the requested
        /// `ratingTarget` unless every attribute saturated at the 25...99 scale.
        var overall: Int
    }

    /// Legal attribute window — the same 25...99 the shared priors clamp to.
    static let bounds: ClosedRange<Int> = 25...99

    /// Spread of a single position-skill draw.
    ///
    /// The random path draws skills uniformly across a 20-point band (σ ≈ 5.8).
    /// Matching that exactly would drown the template's editorial shape: the
    /// `areaHints` have a median max-min gap of 5 points, so at σ = 5.5 only
    /// 83 % of players with a ≥ 4-point hint gap actually come out with the
    /// hinted attribute on top (measured over all 1 807 publish players). At
    /// σ = 4 that rises to 89 % while the within-player spread stays wide enough
    /// that no two skills read as copies — the hints are the whole reason the
    /// transform derived them from real production, so they win the trade.
    static let skillSpread: Double = 4.0

    /// How far the ability offset may be pushed in either direction. Wide enough
    /// that the 55-96 span of template targets is always bracketed.
    private static let offsetSearchRange: ClosedRange<Double> = -45.0...60.0

    /// Halvings of the offset search. 26 pins the crossing point to ~1e-6.
    private static let offsetSearchSteps = 26

    // MARK: - Solve

    static func solve(
        position: Position,
        ratingTarget: Int,
        areaHints: [String: Int],
        levels: Levels,
        seed: UInt64
    ) -> Solution {
        let keys = skillKeys(for: position)

        /// One complete, reproducible draw of the player at ability offset `d`.
        func draw(_ d: Double) -> (skills: [Int], physical: PhysicalAttributes, mental: MentalAttributes) {
            var rng = SeededLeagueRandom(seed: seed)
            let physical = PositionPhysicalProfile.sample(
                for: position, levelShift: levels.physical + d, using: &rng
            )
            let mental = PositionPhysicalProfile.sampleMental(
                for: position, targetAverage: levels.mental + d, using: &rng
            )
            let skills = keys.map { key -> Int in
                let hint = Double(areaHints[key] ?? 0)
                let value = PositionPhysicalProfile.gaussian(
                    mean: levels.skill + d + hint, sd: skillSpread, using: &rng
                )
                return PositionPhysicalProfile.clampInt(PositionPhysicalProfile.softCeiling(value), bounds)
            }
            return (skills, physical, mental)
        }

        var lo = offsetSearchRange.lowerBound
        var hi = offsetSearchRange.upperBound
        for _ in 0..<offsetSearchSteps {
            let mid = (lo + hi) / 2
            let candidate = draw(mid)
            if overall(candidate.skills, candidate.physical, candidate.mental) < ratingTarget {
                lo = mid
            } else {
                hi = mid
            }
        }

        var (skills, physical, mental) = draw(hi)
        tune(toward: ratingTarget, skills: &skills, physical: &physical, mental: &mental)

        return Solution(
            physical: physical,
            mental: mental,
            skills: skills,
            positionAttributes: makePositionAttributes(position, skills),
            overall: overall(skills, physical, mental)
        )
    }

    // MARK: - Overall

    /// `Player.overall` computed from loose parts — identical formula
    /// (50 % position skills, 30 % physical, 20 % mental).
    static func overall(
        _ skills: [Int], _ physical: PhysicalAttributes, _ mental: MentalAttributes
    ) -> Int {
        guard !skills.isEmpty else { return 0 }
        let positionAvg = Double(skills.reduce(0, +)) / Double(skills.count)
        return Int((positionAvg * 0.5 + physical.average * 0.3 + mental.average * 0.2).rounded())
    }

    // MARK: - Fine tune

    /// Closes the last rounding point after the bisection by walking the whole
    /// attribute vector round-robin, ±1 per visit.
    ///
    /// Round-robin rather than "dump the residual on one attribute": for the
    /// handful of 90+ players whose position skills saturate at 99 the residual
    /// has to go somewhere, and spreading it keeps an elite player looking like
    /// an elite athlete instead of growing one freak rating.
    private static func tune(
        toward target: Int,
        skills: inout [Int],
        physical: inout PhysicalAttributes,
        mental: inout MentalAttributes
    ) {
        let slots = skills.count + 12
        var cursor = 0

        for _ in 0..<4_000 {
            let current = overall(skills, physical, mental)
            if current == target { return }
            let step = current < target ? 1 : -1

            var moved = false
            for offset in 0..<slots {
                let index = (cursor + offset) % slots
                if index < skills.count {
                    let next = skills[index] + step
                    if bounds.contains(next) {
                        skills[index] = next
                        moved = true
                    }
                } else if index < skills.count + 6 {
                    moved = adjustPhysical(&physical, slot: index - skills.count, by: step)
                } else {
                    moved = adjustMental(&mental, slot: index - skills.count - 6, by: step)
                }
                if moved {
                    cursor = (index + 1) % slots
                    break
                }
            }
            // Every attribute is saturated in the needed direction — this grid
            // is as close to the target as the 25...99 scale allows.
            if !moved { return }
        }
    }

    private static func adjustPhysical(
        _ attributes: inout PhysicalAttributes, slot: Int, by step: Int
    ) -> Bool {
        func bump(_ value: inout Int) -> Bool {
            let next = value + step
            guard bounds.contains(next) else { return false }
            value = next
            return true
        }
        switch slot {
        case 0:  return bump(&attributes.speed)
        case 1:  return bump(&attributes.acceleration)
        case 2:  return bump(&attributes.strength)
        case 3:  return bump(&attributes.agility)
        case 4:  return bump(&attributes.stamina)
        default: return bump(&attributes.durability)
        }
    }

    private static func adjustMental(
        _ attributes: inout MentalAttributes, slot: Int, by step: Int
    ) -> Bool {
        func bump(_ value: inout Int) -> Bool {
            let next = value + step
            guard bounds.contains(next) else { return false }
            value = next
            return true
        }
        switch slot {
        case 0:  return bump(&attributes.awareness)
        case 1:  return bump(&attributes.decisionMaking)
        case 2:  return bump(&attributes.clutch)
        case 3:  return bump(&attributes.workEthic)
        case 4:  return bump(&attributes.coachability)
        default: return bump(&attributes.leadership)
        }
    }

    // MARK: - Position skills

    /// The game's own attribute names for a position, in declaration order.
    /// These are exactly the keys the transform tool writes into `areaHints`
    /// (verified against the 19 positions in `league_2026_publish.json`; the
    /// snapper and holder post-date that file and have no hints in it, so the
    /// solver falls back to its level-only path for them).
    static func skillKeys(for position: Position) -> [String] {
        switch position {
        case .QB:
            return ["armStrength", "accuracyShort", "accuracyMid", "accuracyDeep", "pocketPresence", "scrambling"]
        case .WR:
            return ["routeRunning", "catching", "release", "spectacularCatch"]
        case .RB, .FB:
            return ["vision", "elusiveness", "breakTackle", "receiving"]
        case .TE:
            return ["blocking", "catching", "routeRunning", "speed"]
        case .LT, .LG, .C, .RG, .RT:
            return ["runBlock", "passBlock", "pull", "anchor"]
        case .DE, .DT:
            return ["passRush", "blockShedding", "powerMoves", "finesseMoves"]
        case .OLB, .MLB:
            return ["tackling", "zoneCoverage", "manCoverage", "blitzing"]
        case .CB, .FS, .SS:
            return ["manCoverage", "zoneCoverage", "press", "ballSkills"]
        case .K, .P:
            return ["kickPower", "kickAccuracy"]
        case .LS:
            return ["snapVelocity", "snapAccuracy"]
        case .H:
            return ["handling", "placement"]
        }
    }

    static func makePositionAttributes(_ position: Position, _ v: [Int]) -> PositionAttributes {
        switch position {
        case .QB:
            return .quarterback(QBAttributes(
                armStrength: v[0], accuracyShort: v[1], accuracyMid: v[2],
                accuracyDeep: v[3], pocketPresence: v[4], scrambling: v[5]
            ))
        case .WR:
            return .wideReceiver(WRAttributes(
                routeRunning: v[0], catching: v[1], release: v[2], spectacularCatch: v[3]
            ))
        case .RB, .FB:
            return .runningBack(RBAttributes(
                vision: v[0], elusiveness: v[1], breakTackle: v[2], receiving: v[3]
            ))
        case .TE:
            return .tightEnd(TEAttributes(
                blocking: v[0], catching: v[1], routeRunning: v[2], speed: v[3]
            ))
        case .LT, .LG, .C, .RG, .RT:
            return .offensiveLine(OLAttributes(
                runBlock: v[0], passBlock: v[1], pull: v[2], anchor: v[3]
            ))
        case .DE, .DT:
            return .defensiveLine(DLAttributes(
                passRush: v[0], blockShedding: v[1], powerMoves: v[2], finesseMoves: v[3]
            ))
        case .OLB, .MLB:
            return .linebacker(LBAttributes(
                tackling: v[0], zoneCoverage: v[1], manCoverage: v[2], blitzing: v[3]
            ))
        case .CB, .FS, .SS:
            return .defensiveBack(DBAttributes(
                manCoverage: v[0], zoneCoverage: v[1], press: v[2], ballSkills: v[3]
            ))
        case .K, .P:
            return .kicking(KickingAttributes(kickPower: v[0], kickAccuracy: v[1]))
        case .LS:
            return .snapping(SnapAttributes(snapVelocity: v[0], snapAccuracy: v[1]))
        case .H:
            return .holding(HoldAttributes(handling: v[0], placement: v[1]))
        }
    }
}
