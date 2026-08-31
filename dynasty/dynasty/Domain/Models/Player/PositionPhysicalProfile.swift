import Foundation

/// Shared per-position physical priors — `docs/DRAFT_CLASS_OVERHAUL_PLAN.md` §4.
///
/// One table feeds BOTH veteran generation (`LeagueGenerator`) and draft-class
/// generation (`DraftClassBuilder`) so rookies and veterans are drawn from the
/// same distributions. Before this existed, every player at every position got
/// `PhysicalAttributes.random()` (uniform 40...99), which meant an interior
/// lineman was as likely to be a 95-speed athlete as a cornerback.
///
/// The table describes a position's **body shape** (a CB is fast and light, an
/// interior lineman is strong and slow) plus a `level` shift that expresses how
/// good the athlete is. `sample(for:levelShift:)` returns
/// `prior.mean + levelShift + N(0, prior.sd)`, so a shift of `0` reproduces the
/// reference means verbatim.
///
/// Calibration note: weighted by the 53-man roster blueprint the table's means
/// average to 70.5 — within 1.0 point of the historical uniform mean (69.5)
/// that veteran `overall` values were tuned against, i.e. +0.3 OVR league-wide
/// (physical carries 30 % of `Player.overall`). Individual positions do move:
/// K/P −3.7, IOL −2.1, OT −1.9, WR/CB +1.6.
enum PositionPhysicalProfile {

    // MARK: - Prior

    /// A single attribute prior: normal(mean, sd), truncated by the caller.
    struct Prior {
        let mean: Double
        let sd: Double

        init(_ mean: Double, _ sd: Double) {
            self.mean = mean
            self.sd = sd
        }
    }

    /// The six physical attributes' priors for one position.
    struct Profile {
        let speed: Prior
        let acceleration: Prior
        let strength: Prior
        let agility: Prior
        let stamina: Prior
        let durability: Prior

        /// Average of the six means — the position's natural physical level.
        var meanAverage: Double {
            (speed.mean + acceleration.mean + strength.mean
                + agility.mean + stamina.mean + durability.mean) / 6.0
        }
    }

    /// Historical league-wide physical mean (`PhysicalAttributes.random()` on
    /// 40...99). Veteran generation anchors its level shifts to this value so
    /// migrating onto the shared table does not move league average overall.
    static let baseLevel: Double = 69.5

    /// Stamina / durability are position-independent per the plan (70±8, 72±9).
    private static let staminaPrior = Prior(70, 8)
    private static let durabilityPrior = Prior(72, 9)

    // MARK: - Table

    /// Per-position physical priors (mean ± σ) from plan §4.
    static func profile(for position: Position) -> Profile {
        switch position {
        case .QB:
            return Profile(speed: Prior(62, 8), acceleration: Prior(68, 7),
                           strength: Prior(55, 8), agility: Prior(68, 7),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .RB:
            return Profile(speed: Prior(82, 5), acceleration: Prior(84, 5),
                           strength: Prior(66, 7), agility: Prior(82, 5),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .FB:
            return Profile(speed: Prior(62, 6), acceleration: Prior(66, 6),
                           strength: Prior(76, 6), agility: Prior(60, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .WR:
            return Profile(speed: Prior(85, 5), acceleration: Prior(86, 5),
                           strength: Prior(52, 7), agility: Prior(84, 5),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .TE:
            return Profile(speed: Prior(70, 6), acceleration: Prior(72, 6),
                           strength: Prior(72, 6), agility: Prior(66, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .LT, .RT:
            return Profile(speed: Prior(47, 6), acceleration: Prior(52, 6),
                           strength: Prior(84, 5), agility: Prior(54, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .LG, .C, .RG:
            return Profile(speed: Prior(45, 6), acceleration: Prior(50, 6),
                           strength: Prior(86, 5), agility: Prior(52, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .DE:
            return Profile(speed: Prior(73, 6), acceleration: Prior(76, 6),
                           strength: Prior(78, 6), agility: Prior(72, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .DT:
            return Profile(speed: Prior(55, 7), acceleration: Prior(62, 7),
                           strength: Prior(87, 5), agility: Prior(58, 7),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .OLB:
            return Profile(speed: Prior(76, 5), acceleration: Prior(78, 5),
                           strength: Prior(74, 6), agility: Prior(74, 5),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .MLB:
            return Profile(speed: Prior(73, 5), acceleration: Prior(75, 5),
                           strength: Prior(75, 6), agility: Prior(71, 5),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .CB:
            return Profile(speed: Prior(86, 4), acceleration: Prior(87, 4),
                           strength: Prior(48, 7), agility: Prior(85, 4),
                           stamina: staminaPrior, durability: durabilityPrior)
        case .FS, .SS:
            return Profile(speed: Prior(82, 5), acceleration: Prior(83, 5),
                           strength: Prior(58, 7), agility: Prior(80, 5),
                           stamina: staminaPrior, durability: durabilityPrior)
        // The holder is a kicking-room body — in the real game he is usually the
        // punter — so he shares the specialists' shape rather than getting an
        // invented one.
        case .K, .P, .H:
            return Profile(speed: Prior(50, 8), acceleration: Prior(52, 8),
                           strength: Prior(45, 8), agility: Prior(55, 8),
                           stamina: staminaPrior, durability: durabilityPrior)
        // The snapper is not: he is a tight end / centre body who has to fire
        // the ball back and then get downfield, so he sits between the two.
        case .LS:
            return Profile(speed: Prior(60, 7), acceleration: Prior(64, 6),
                           strength: Prior(74, 6), agility: Prior(62, 6),
                           stamina: staminaPrior, durability: durabilityPrior)
        }
    }

    // MARK: - Mental shape

    /// Mental priors (plan §4). Awareness is position-aware (QB/S/MLB/C read the
    /// whole field); the rest are league-wide. Used as a *shape* around a level
    /// so the mean can be scaled with talent without losing the position tilt.
    struct MentalProfile {
        let awareness: Prior
        let decisionMaking: Prior
        let clutch: Prior
        let workEthic: Prior
        let coachability: Prior
        let leadership: Prior

        var meanAverage: Double {
            (awareness.mean + decisionMaking.mean + clutch.mean
                + workEthic.mean + coachability.mean + leadership.mean) / 6.0
        }
    }

    static func mentalProfile(for position: Position) -> MentalProfile {
        let awarenessMean: Double
        switch position {
        case .QB, .FS, .SS, .MLB, .C: awarenessMean = 62
        default:                      awarenessMean = 56
        }
        return MentalProfile(
            awareness: Prior(awarenessMean, 9),
            decisionMaking: Prior(56, 9),
            clutch: Prior(55, 10),
            workEthic: Prior(58, 11),
            coachability: Prior(58, 10),
            leadership: Prior(52, 11)
        )
    }

    // MARK: - Sampling

    /// Samples physical attributes for a position.
    /// - Parameters:
    ///   - position: The position whose body shape to draw.
    ///   - levelShift: Points added to every prior mean. `0` gives the reference
    ///     means; positive values make a better athlete.
    ///   - spread: Multiplier on the per-attribute σ (1.0 = full prior spread).
    ///   - bounds: Hard clamp applied to every attribute.
    static func sample(
        for position: Position,
        levelShift: Double = 0,
        spread: Double = 1.0,
        bounds: ClosedRange<Int> = 25...99
    ) -> PhysicalAttributes {
        var rng = SystemRandomNumberGenerator()
        return sample(
            for: position, levelShift: levelShift, spread: spread, bounds: bounds, using: &rng
        )
    }

    /// Seeded variant of `sample(for:levelShift:spread:bounds:)` — identical
    /// math, driven by a caller-owned generator.
    ///
    /// Exists for the fixed-league template import (`LeagueTemplateImporter`),
    /// which must produce byte-identical attributes on every run. Routing it
    /// through the SAME priors and the SAME `softCeiling` as the random path is
    /// the whole point: a template player and a generated player are drawn from
    /// one distribution, only the entropy source differs.
    static func sample<G: RandomNumberGenerator>(
        for position: Position,
        levelShift: Double = 0,
        spread: Double = 1.0,
        bounds: ClosedRange<Int> = 25...99,
        using generator: inout G
    ) -> PhysicalAttributes {
        let p = profile(for: position)
        func draw(_ prior: Prior) -> Int {
            clampInt(
                softCeiling(
                    gaussian(mean: prior.mean + levelShift, sd: prior.sd * spread, using: &generator)
                ),
                bounds
            )
        }
        return PhysicalAttributes(
            speed: draw(p.speed),
            acceleration: draw(p.acceleration),
            strength: draw(p.strength),
            agility: draw(p.agility),
            stamina: draw(p.stamina),
            durability: draw(p.durability)
        )
    }

    /// Samples mental attributes for a position around a target average.
    /// - Parameters:
    ///   - targetAverage: The desired average of the six mental attributes.
    ///   - spread: Multiplier on the per-attribute σ.
    static func sampleMental(
        for position: Position,
        targetAverage: Double,
        spread: Double = 1.0,
        bounds: ClosedRange<Int> = 25...99
    ) -> MentalAttributes {
        var rng = SystemRandomNumberGenerator()
        return sampleMental(
            for: position, targetAverage: targetAverage, spread: spread, bounds: bounds, using: &rng
        )
    }

    /// Seeded variant of `sampleMental(for:targetAverage:spread:bounds:)`.
    static func sampleMental<G: RandomNumberGenerator>(
        for position: Position,
        targetAverage: Double,
        spread: Double = 1.0,
        bounds: ClosedRange<Int> = 25...99,
        using generator: inout G
    ) -> MentalAttributes {
        let p = mentalProfile(for: position)
        let shift = targetAverage - p.meanAverage
        func draw(_ prior: Prior) -> Int {
            clampInt(gaussian(mean: prior.mean + shift, sd: prior.sd * spread, using: &generator), bounds)
        }
        return MentalAttributes(
            awareness: draw(p.awareness),
            decisionMaking: draw(p.decisionMaking),
            clutch: draw(p.clutch),
            workEthic: draw(p.workEthic),
            coachability: draw(p.coachability),
            leadership: draw(p.leadership)
        )
    }

    // MARK: - Anthropometrics

    /// Height (inches) / weight (pounds) ranges per position.
    /// Moved here from `ScoutingEngine` so prospects and veterans read one table.
    static func heightWeightRange(for position: Position) -> (height: ClosedRange<Int>, weight: ClosedRange<Int>) {
        switch position {
        case .QB:  return (73...77, 205...240)
        case .RB:  return (68...73, 195...230)
        case .FB:  return (71...74, 235...260)
        case .WR:  return (69...76, 175...215)
        case .TE:  return (74...78, 235...265)
        case .LT, .RT: return (76...80, 295...340)
        case .LG, .RG: return (74...78, 295...335)
        case .C:   return (73...77, 290...320)
        case .DE:  return (74...79, 250...285)
        case .DT:  return (73...77, 280...330)
        case .OLB: return (73...77, 230...260)
        case .MLB: return (72...76, 235...260)
        case .CB:  return (69...74, 180...205)
        case .FS:  return (71...75, 195...215)
        case .SS:  return (71...75, 200...225)
        case .K:   return (71...75, 185...215)
        case .P:   return (72...76, 200...225)
        case .LS:  return (73...77, 235...260)
        case .H:   return (72...76, 195...220)
        }
    }

    // MARK: - Random helpers

    /// Box–Muller normal draw. Shared by every generator that samples a prior.
    static func gaussian(mean: Double, sd: Double) -> Double {
        var rng = SystemRandomNumberGenerator()
        return gaussian(mean: mean, sd: sd, using: &rng)
    }

    /// Seeded Box–Muller draw — the same two uniforms, from a caller-owned
    /// generator. `gaussian(mean:sd:)` forwards here with the system RNG, so
    /// the random and template paths execute identical arithmetic.
    static func gaussian<G: RandomNumberGenerator>(
        mean: Double, sd: Double, using generator: inout G
    ) -> Double {
        guard sd > 0 else { return mean }
        let u1 = max(Double.random(in: 0...1, using: &generator), 1e-9)
        let u2 = Double.random(in: 0...1, using: &generator)
        let z = (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
        return mean + z * sd
    }

    /// Normal draw truncated to ±`limit` standard deviations (no runaway tails).
    static func truncatedGaussian(mean: Double, sd: Double, limit: Double = 3.0) -> Double {
        var rng = SystemRandomNumberGenerator()
        return truncatedGaussian(mean: mean, sd: sd, limit: limit, using: &rng)
    }

    /// Seeded variant of `truncatedGaussian(mean:sd:limit:)`.
    static func truncatedGaussian<G: RandomNumberGenerator>(
        mean: Double, sd: Double, limit: Double = 3.0, using generator: inout G
    ) -> Double {
        let raw = gaussian(mean: mean, sd: sd, using: &generator)
        let lo = mean - sd * limit
        let hi = mean + sd * limit
        return Swift.min(hi, Swift.max(lo, raw))
    }

    /// Point above which the 25…99 scale stops being linear.
    private static let softCeilingPivot: Double = 92.0

    /// Squeezes draws that overshoot the 99 ceiling into `pivot…99` instead of
    /// letting them pile up ON 99.
    ///
    /// The draft generator drives a position's priors with a talent-scaled level
    /// shift, and the fast positions start close to the top already (CB speed
    /// 86 ± 4). A first-round corner's speed prior therefore lands well past 99,
    /// and a hard clamp collapsed the entire top of the board onto one value:
    /// measured 55 % of top-12 corners and 52 % of top-12 receivers had speed
    /// **exactly 99**, so the #1 and the #12 corner drew their 40 times from an
    /// identical distribution and the drill results carried no ordering at all.
    ///
    /// `tanh` keeps the map strictly increasing (derivative 1 at the pivot), so
    /// a better draw is still a better attribute — it just costs progressively
    /// more above the pivot. Below the pivot the function is the identity, so
    /// veteran generation (level shifts of ±3) is untouched.
    ///
    /// Measured over 200 classes with the pivot at 92: top-12 corners pinned on
    /// 99 drop 55 % → 7 %, receivers 52 % → 8 %, and the share of *all six*
    /// physicals sitting on 99 across slots 1–5 drops 18.6 % → 3.4 %, while
    /// harness assert §7.7c (`corr(speed, 40 time) ≤ −0.6`) keeps its margin at
    /// −0.63…−0.65. A lower pivot removes the last of the pinning but costs that
    /// margin — 88 measured −0.62 against a −0.60 floor.
    static func softCeiling(_ value: Double, pivot: Double? = nil, ceiling: Double = 99.0) -> Double {
        let p = pivot ?? softCeilingPivot
        guard value > p else { return value }
        let headroom = ceiling - p
        guard headroom > 0 else { return ceiling }
        return p + headroom * tanh((value - p) / headroom)
    }

    static func clampInt(_ value: Double, _ bounds: ClosedRange<Int>) -> Int {
        let rounded = Int(value.rounded())
        return Swift.min(bounds.upperBound, Swift.max(bounds.lowerBound, rounded))
    }
}
