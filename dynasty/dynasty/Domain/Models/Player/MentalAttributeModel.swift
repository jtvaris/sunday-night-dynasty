import Foundation

/// Shared generator for the two "mental software" ratings that live outside
/// `MentalAttributes` — `learning` and `competitiveness`.
///
/// Why this exists (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §1.3 defect #7,
/// §2.2): before it, three cohorts generated `learning` three different ways —
/// `LeagueGenerator` used `0.6·awareness + 0.4·U[40,99]`, `DraftClassBuilder`
/// used the validated `0.40·awareness + 0.60·N(level, 15)`, and the legacy
/// backfill used a hashed variant of the first. A drafted rookie and a
/// generated veteran with identical awareness therefore installed schemes at
/// systematically different rates, purely because of which code path created
/// them. Every cohort now calls the functions below, so the whole league is
/// drawn from ONE distribution.
///
/// Deliberately free of any dependency on `Player` / `CollegeProspect`: it is a
/// pure math enum over `PersonalityArchetype` + `PositionPhysicalProfile`, so
/// the balance harness can compile it verbatim alongside `DraftClassBuilder`.
/// `Player.storedLearning` / `Player.storedCompetitiveness` forward here.
enum MentalAttributeModel {

    // MARK: - Sentinels

    /// The `learning` value a row carries when nothing has ever written one.
    static let defaultLearning = 55

    /// The `competitiveness` value a row carries when nothing has ever written
    /// one. Same sentinel trick as `defaultLearning`.
    static let defaultCompetitiveness = 55

    /// Normalises a generated learning rating into `bounds` and nudges it off
    /// `defaultLearning`, so a written value can never be mistaken for an
    /// unwritten one. The one-point gap at 55 is invisible in play and makes
    /// `WeekAdvancer.backfillLegacyLearning` provably idempotent.
    static func storedLearning(_ value: Int, bounds: ClosedRange<Int> = 25...99) -> Int {
        let clamped = min(bounds.upperBound, max(bounds.lowerBound, value))
        return clamped == defaultLearning ? defaultLearning + 1 : clamped
    }

    /// Sentinel-safe clamp for competitiveness — mirrors `storedLearning`, so
    /// `WeekAdvancer.backfillLegacyCompetitiveness` is idempotent too.
    static func storedCompetitiveness(_ value: Int, bounds: ClosedRange<Int> = 25...99) -> Int {
        let clamped = min(bounds.upperBound, max(bounds.lowerBound, value))
        return clamped == defaultCompetitiveness ? defaultCompetitiveness + 1 : clamped
    }

    // MARK: - Learning

    /// Spread of the independent learning draw (plan §2.2). Calibration note
    /// from phase 1: the plan's literal `0.6·awareness + 0.4·draw` measures
    /// r ≈ 0.87 against awareness in a full draft class, because awareness and
    /// the draw share the same talent-driven mental level — learning would then
    /// be a near-duplicate of awareness. `0.40 / 0.60` with this wider draw
    /// restores the specified r ≈ 0.6 (measured 0.62 over 120 classes).
    static let learningDrawSD: Double = 15

    private static let awarenessWeight: Double = 0.40
    private static let drawWeight: Double = 0.60

    /// Playbook-absorption rating (25-99), correlated r ≈ 0.6 with `awareness`
    /// but deliberately not a duplicate of it.
    ///
    /// - Parameters:
    ///   - awareness: The player's game-IQ attribute.
    ///   - level: The mental level the independent draw is centred on. Draft
    ///     prospects pass the generator's `mentalLevel`; generated veterans and
    ///     the legacy backfill pass the player's own mental average.
    ///   - shift: Archetype / position tilt added before the clamp.
    ///   - seed: When non-nil, the draw is derived deterministically from this
    ///     value (a UUID byte) instead of the RNG, so a backfill pass writes the
    ///     same number every time it runs.
    static func learning(
        awareness: Int,
        level: Double,
        shift: Double = 0,
        seed: Int? = nil
    ) -> Int {
        var rng = SystemRandomNumberGenerator()
        return learning(awareness: awareness, level: level, shift: shift, seed: seed, using: &rng)
    }

    /// Seeded variant of `learning(awareness:level:shift:seed:)` — same formula,
    /// caller-owned entropy. Used by the fixed-league template import so a
    /// veteran's playbook-absorption rating is constant across imports.
    static func learning<G: RandomNumberGenerator>(
        awareness: Int,
        level: Double,
        shift: Double = 0,
        seed: Int? = nil,
        using generator: inout G
    ) -> Int {
        let draw = seed.map { seededDraw(around: level, sd: learningDrawSD, seed: $0) }
            ?? PositionPhysicalProfile.gaussian(mean: level, sd: learningDrawSD, using: &generator)
        let value = awarenessWeight * Double(awareness) + drawWeight * draw + shift
        return storedLearning(Int(value.rounded()))
    }

    // MARK: - Competitiveness

    /// The fighter-mentality stat (25-99): drives adversity response,
    /// complacency immunity and plateau-break (plan §2.1). Blends the player's
    /// own drive attributes (work ethic 0.45, clutch 0.25) with an independent
    /// draw (0.30) and the personality tilt, so two players with identical
    /// mental grids can still respond differently to a lost season.
    ///
    /// - Parameters:
    ///   - archetype: Personality archetype supplying the shift.
    ///   - workEthic: `MentalAttributes.workEthic`.
    ///   - clutch: `MentalAttributes.clutch`.
    ///   - seed: When non-nil, the independent draw is derived deterministically
    ///     from this value (a UUID byte) and spans 30...85 uniformly — the
    ///     legacy-backfill path from plan §2.1. When nil the draw is
    ///     `N(mental core, 12)`, the prospect-generation path.
    ///   - bounds: Final clamp (prospects 25...99, backfilled legacy 25...95).
    static func competitiveness(
        archetype: PersonalityArchetype,
        workEthic: Int,
        clutch: Int,
        seed: Int? = nil,
        bounds: ClosedRange<Int> = 25...99
    ) -> Int {
        var rng = SystemRandomNumberGenerator()
        return competitiveness(
            archetype: archetype, workEthic: workEthic, clutch: clutch,
            seed: seed, bounds: bounds, using: &rng
        )
    }

    /// Seeded variant of `competitiveness(archetype:workEthic:clutch:seed:bounds:)`.
    static func competitiveness<G: RandomNumberGenerator>(
        archetype: PersonalityArchetype,
        workEthic: Int,
        clutch: Int,
        seed: Int? = nil,
        bounds: ClosedRange<Int> = 25...99,
        using generator: inout G
    ) -> Int {
        let draw: Double
        if let seed {
            // Uniform 30...85 straight off the hash — the plan's backfill shape.
            draw = 30.0 + unitFraction(seed) * 55.0
        } else {
            draw = PositionPhysicalProfile.truncatedGaussian(
                mean: competitivenessDrawMean, sd: competitivenessDrawSD, limit: 2.2,
                using: &generator
            )
        }
        let value = competitivenessDriveWeight * Double(workEthic)
            + competitivenessClutchWeight * Double(clutch)
            + competitivenessDrawWeight * draw
            + competitivenessShift(for: archetype)
        return storedCompetitiveness(Int(value.rounded()), bounds: bounds)
    }

    /// Centre and spread of the INDEPENDENT competitiveness draw.
    ///
    /// **Calibration (plan §5 stage 5, `career` harness).** The plan specified a
    /// gaussian "around the prospect's mental level, sd 12" with weights
    /// 0.45/0.25/0.30 on work ethic / clutch / draw. All three terms then track
    /// talent, so competitiveness became a proxy for it: measured over a
    /// 30-season league the surviving population sat at p50 = 77, and the §2.3
    /// trigger table — written in absolutes ("comp ≥ 65 answers adversity",
    /// "comp ≤ 40 checks out") — selected **82 %** of the league as fighters and
    /// **0 %** as checked-out. The motivation mix came out driven 30 % /
    /// focused 70 % / complacent 0.2 % / discouraged 0 %, i.e. three of the four
    /// designed states were unreachable.
    ///
    /// Recentring the draw on a FIXED league mean and widening it makes
    /// competitiveness the independent fighter trait §2.1 describes: the
    /// measured league then lands ≈ p50 62, with the plan's own gates selecting
    /// roughly the top third and the bottom eighth. `DEVELOPMENT_NFL_REFERENCE.md`
    /// §4 is explicit that the response to adversity is a *separate* axis from
    /// talent — the Brady/Rice archetype is the point of the stat.
    static let competitivenessDrawMean: Double = 50
    static let competitivenessDrawSD: Double = 24

    /// Weights on the drive/nerve/independent terms. The independent draw now
    /// carries the majority, so two players with identical mental grids really
    /// can answer a lost season differently.
    static let competitivenessDriveWeight: Double = 0.30
    static let competitivenessClutchWeight: Double = 0.15
    static let competitivenessDrawWeight: Double = 0.55

    /// Personality tilt on competitiveness (plan §2.1). The fighters and the
    /// culture-setters push up, the vibes-driven and the jokers push down;
    /// everyone else is neutral so the league mean is unmoved.
    static func competitivenessShift(for archetype: PersonalityArchetype) -> Double {
        switch archetype {
        case .fieryCompetitor, .teamLeader:      return 12
        case .mentor, .steadyPerformer:          return 5
        case .feelPlayer, .classClown:           return -6
        case .loneWolf, .dramaQueen, .quietProfessional: return 0
        }
    }

    // MARK: - Deterministic draws

    /// Maps a seed byte to `0.0...1.0`. Callers pass a UUID byte, so two
    /// different attributes must read two different bytes to stay uncorrelated.
    private static func unitFraction(_ seed: Int) -> Double {
        let byte = ((seed % 256) + 256) % 256
        return Double(byte) / 255.0
    }

    /// Deterministic stand-in for a gaussian draw: the seed byte is spread
    /// uniformly across ±1.7 σ, which has standard deviation
    /// `1.7·σ/√3 ≈ 0.98·σ` — i.e. a backfilled row lands inside the same
    /// distribution the RNG path samples, without ever moving between passes.
    private static func seededDraw(around mean: Double, sd: Double, seed: Int) -> Double {
        let t = unitFraction(seed) * 2.0 - 1.0     // -1 … +1
        return mean + t * 1.7 * sd
    }
}
