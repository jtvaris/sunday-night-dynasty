import Foundation

/// R23 — Makes the FA signing model visible.
///
/// Computes a 0...1 "interest" reading for how warm a free agent is on the
/// user's team, built from the same factors the decision engine weighs:
/// money vs. the asking price, the team's success last season, the projected
/// role (is a better player already ahead at the position?), scheme fit when
/// the coaching staff runs a known scheme, and a hosted facility visit.
/// The weights shift with the player's motivation so the meter explains the
/// eventual decision instead of contradicting it.
///
/// One last, smaller term reads the city rather than the roster: how the user's
/// own fan base currently feels about his front office. See
/// ``fanSupportBonus(_:)`` for its size and for why it is the only term in here
/// that can apply to exactly one of the league's 32 clubs.
///
/// A second small term reads the BUILDING rather than the city: whether this
/// coaching staff has a name for making players better. It invents nothing —
/// the number is `CoachingEngine.developmentAppeal`, already derived from the
/// staff's development attributes blended with what the young men on their
/// watch actually gained, and already the weight the AI-vs-AI market picks a
/// destination with. See ``developerReputationBonus(_:)``.
enum SigningInterestEngine {

    // MARK: - Tiers

    enum InterestTier: String {
        case cold      = "Cold"
        case lukewarm  = "Lukewarm"
        case warm      = "Warm"
        case hot       = "Hot"
        case scorching = "Scorching"

        static func tier(for score: Double) -> InterestTier {
            switch score {
            case ..<0.30: return .cold
            case ..<0.45: return .lukewarm
            case ..<0.62: return .warm
            case ..<0.80: return .hot
            default:      return .scorching
            }
        }

        /// SF Symbol used in meters and chips.
        var icon: String {
            switch self {
            case .cold:      return "snowflake"
            case .lukewarm:  return "thermometer.low"
            case .warm:      return "thermometer.medium"
            case .hot:       return "thermometer.high"
            case .scorching: return "flame.fill"
            }
        }
    }

    // MARK: - Breakdown

    struct Breakdown {
        /// Factor readings, each 0...1.
        let money: Double
        let teamSuccess: Double
        let role: Double
        /// `nil` when the team has no known scheme (treated as neutral 0.5).
        let schemeFit: Double?
        /// Flat bonus applied when the player was hosted on a visit.
        let visitBonus: Double
        /// Signed nudge from the city's read on the user's front office,
        /// -0.05...+0.05. Exactly 0 for all 31 other clubs — see
        /// ``SigningInterestEngine/fanSupportBonus(_:)``.
        let fanSupportBonus: Double
        /// Signed nudge from the coaching staff's reputation for developing
        /// players, -0.05...+0.05. Exactly 0 for a club nobody has rated — see
        /// ``SigningInterestEngine/developerReputationBonus(_:)``.
        let developerReputationBonus: Double
        /// Weighted total, clamped 0...1.
        let total: Double

        var tier: InterestTier { InterestTier.tier(for: total) }
    }

    // MARK: - Candidate

    /// The four things the interest math actually reads off a man, as a value.
    ///
    /// Introduced for the UDFA market (#204, `OFFSEASON_ROSTER_PLAN.md` §2.2).
    /// That market prices **prospects**: a `CollegeProspect` has no `Player` row
    /// and must not be given one before he is signed — a `Player` carries true
    /// attributes past the fog (invariant 5), and building ~110 of them just to
    /// price a market would claim ~110 faces a season through
    /// `DraftEngine.copyProspectMetadata` for men nobody ever signs.
    ///
    /// This is a **refactor, not a second copy of the math**: `interest(player:…)`
    /// and `roleScore(player:…)` below build a `Candidate` and delegate, so every
    /// existing caller keeps its exact behaviour and there is still exactly one
    /// place where an interest score is computed.
    struct Candidate {
        let id: UUID
        let position: Position
        /// TRUE overall — engine-side only. Nothing rendered is ever derived from
        /// it: the UDFA board reads `scouted*` bands off the prospect instead.
        let overall: Int
        let motivation: Motivation

        init(id: UUID, position: Position, overall: Int, motivation: Motivation) {
            self.id = id
            self.position = position
            self.overall = overall
            self.motivation = motivation
        }

        init(player: Player) {
            self.init(
                id: player.id,
                position: player.position,
                overall: player.overall,
                motivation: player.personality.motivation
            )
        }
    }

    // MARK: - Interest

    /// Interest reading for a free agent considering `team`.
    /// - Parameters:
    ///   - offer: The user's current offer; `nil` shows the pre-offer baseline.
    ///   - askingPrice: The agent's asking price (thousands/yr).
    ///   - hostedVisit: Whether the team hosted the player on a facility visit.
    ///   - fanSupport: The user's `Career.fanSupport` when `team` IS the user's
    ///     club; `nil` — the default, and the truth for the other 31 — leaves the
    ///     reading exactly where it was. See ``fanSupportBonus(_:)``.
    ///   - developmentAppeal: `CoachingEngine.developmentAppeal(teamID:coaches:)`
    ///     for `team`. Unlike `fanSupport` every club has one, so a caller that
    ///     ranks clubs against each other must pass it for all of them or none.
    ///     See ``developerReputationBonus(_:)``.
    static func interest(
        player: Player,
        askingPrice: Int,
        offer: (salary: Int, years: Int)?,
        team: Team,
        allPlayers: [Player],
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        hostedVisit: Bool = false,
        fanSupport: Int? = nil,
        developmentAppeal: Double? = nil
    ) -> Breakdown {
        // Scheme fit when the staff runs a known scheme. Computed here, at the
        // one entry point that has a `Player` to hand it to `CoachingEngine`.
        let scheme: Double?
        if offensiveScheme != nil || defensiveScheme != nil {
            scheme = CoachingEngine.schemeFit(
                player: player,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme
            )
        } else {
            scheme = nil
        }

        return interest(
            candidate: Candidate(player: player),
            askingPrice: askingPrice,
            offer: offer,
            team: team,
            allPlayers: allPlayers,
            schemeFit: scheme,
            hostedVisit: hostedVisit,
            fanSupport: fanSupport,
            developmentAppeal: developmentAppeal
        )
    }

    /// The interest math, over a value input.
    ///
    /// - Parameter schemeFit: `nil` when nobody can say how this man fits the
    ///   system — treated as the documented neutral 0.5. The UDFA market passes
    ///   `nil` deliberately (§2.2): `CoachingEngine.schemeFit` needs a `Player`'s
    ///   attributes, and an undrafted rookie's scheme fit is not something any
    ///   club actually knows on the night he signs. Recorded here as a stated
    ///   simplification rather than a silent one.
    static func interest(
        candidate: Candidate,
        askingPrice: Int,
        offer: (salary: Int, years: Int)?,
        team: Team,
        allPlayers: [Player],
        schemeFit: Double? = nil,
        hostedVisit: Bool = false,
        fanSupport: Int? = nil,
        developmentAppeal: Double? = nil
    ) -> Breakdown {
        // Money: offer vs. asking. 0.6x -> 0.0, 1.0x -> ~0.67, 1.2x+ -> 1.0.
        let money: Double
        if let offer {
            let ratio = Double(offer.salary) / Double(max(askingPrice, 1))
            money = clamp01((ratio - 0.6) / 0.6)
        } else {
            money = 0.45 // no offer on the table yet
        }

        // Team success: last season's win percentage (records reset only at
        // the start of the next regular season, so they hold through FA).
        let games = team.wins + team.losses + team.ties
        let teamSuccess = games > 0 ? Double(team.wins) / Double(games) : 0.5

        // Role: would he start here, or is a better player ahead of him?
        let role = roleScore(candidate: candidate, teamID: team.id, allPlayers: allPlayers)

        // Motivation-shifted weights (money, success, role, scheme).
        let weights: (money: Double, success: Double, role: Double, scheme: Double)
        switch candidate.motivation {
        case .money:   weights = (0.60, 0.10, 0.15, 0.15)
        case .winning: weights = (0.35, 0.35, 0.15, 0.15)
        case .stats:   weights = (0.35, 0.10, 0.35, 0.20)
        case .loyalty: weights = (0.45, 0.15, 0.20, 0.20)
        case .fame:    weights = (0.50, 0.20, 0.15, 0.15)
        }

        var total = money * weights.money
            + teamSuccess * weights.success
            + role * weights.role
            + (schemeFit ?? 0.5) * weights.scheme

        let visitBonus = hostedVisit ? 0.12 : 0.0
        // Added BESIDE `visitBonus` rather than folded in as a fifth weight, and
        // that is a decision, not laziness: a fifth weight means renormalizing
        // the four above, which would move every existing reading even for a club
        // sitting at the neutral 50, and there is no fan number for the other 31
        // clubs to renormalize against. As a signed term through the same clamp,
        // a neutral (or absent) city is arithmetically identical to no term.
        let fanBonus = fanSupportBonus(fanSupport)
        // The building, beside the city and for the same structural reason: a
        // weight of its own would have to renormalise the four above, and a club
        // whose staff nobody has rated has no number to renormalise against.
        // Through the same clamp, an unrated — or exactly league-average —
        // staff is arithmetically identical to no term at all.
        let developerBonus = developerReputationBonus(developmentAppeal)
        total = clamp01(total + visitBonus + fanBonus + developerBonus)

        return Breakdown(
            money: money,
            teamSuccess: teamSuccess,
            role: role,
            schemeFit: schemeFit,
            visitBonus: visitBonus,
            fanSupportBonus: fanBonus,
            developerReputationBonus: developerBonus,
            total: total
        )
    }

    // MARK: - Fan support

    /// Largest nudge the fan-support term can apply, at 0 or 100.
    ///
    /// Calibrated against the terms already inside `interest`, not picked for
    /// feel: it is under half the hosted-visit bonus (0.12), a twelfth of a
    /// money-motivated man's money weight (0.60), and a third of the narrowest
    /// tier band (~0.15). So a sold-out city can carry a man up a tier
    /// only when he was already sitting on that tier's edge, and can never
    /// out-argue the cheque, the depth chart or the scheme. Tilting a close call
    /// is the whole brief.
    private static let fanSupportSwing = 0.05

    /// What the city's read on the front office is worth, as a signed nudge on
    /// the 0...1 interest scale. Linear through the neutral 50.
    ///
    /// **Asymmetric on purpose.** `fanSupport` is a field on `Career` — the
    /// USER's save, moved by his own press conferences. No AI club has one. So
    /// `nil` here does not mean "unknown", it means "this is not the user's
    /// building", and it returns exactly 0: all 31 other clubs price a free agent
    /// precisely as they did before this term existed. Inventing a league-wide
    /// fan model to make the term symmetric is a far larger design decision than
    /// giving the podium's FANS number something to do, and is deliberately not
    /// smuggled in here.
    ///
    /// Deliberately NOT motivation-shifted, unlike the weights in `interest`: no
    /// motivation in the model is "plays in front of a full house". The nearest,
    /// `.fame`, is already served by `MediaMarket.freeAgentAttraction` over in
    /// `FreeAgencyEngine`, and this must not quietly double it — that term is
    /// about WHERE a club plays and never changes, this one is about how the city
    /// feels about it this month.
    static func fanSupportBonus(_ fanSupport: Int?) -> Double {
        guard let fanSupport else { return 0 }
        let tilt = (Double(min(max(fanSupport, 0), 100)) - 50.0) / 50.0 // -1...+1
        return tilt * fanSupportSwing
    }

    // MARK: - Developer reputation

    /// Largest nudge a staff's developer reputation can apply, at the ends of
    /// `CoachingEngine.developmentAppealRange`.
    ///
    /// Deliberately the SAME size as `fanSupportSwing`. The classroom and the
    /// city are the two things a club can put in a pitch that are not money,
    /// role or scheme, and neither has a claim to outrank the other. Together
    /// they come to 0.10 — still under the 0.12 a hosted visit is worth, so
    /// everything a club can *say* about itself stays cheaper than actually
    /// walking the man through the building.
    ///
    /// ±0.05 is the theoretical extreme and needs a staff score of 1 or 99,
    /// which no generated staff reaches. What the market actually feels is the
    /// middle of the mapping: a league-average staff (50) is exactly 0, a
    /// genuinely strong one (~75) is +0.025, an elite one (~90) is +0.04. In
    /// cash that is about a 4 % discount on the asking price to a
    /// money-motivated man (whose money weight is 0.60) and about 7 % to one
    /// chasing a ring (0.35) — real money, and nowhere near enough to be the
    /// reason he signs.
    private static let developerReputationSwing = 0.05

    /// What a coaching staff's reputation for developing players is worth to a
    /// free agent, as a signed nudge on the 0...1 interest scale.
    ///
    /// - Parameter developmentAppeal: `CoachingEngine.developmentAppeal` for the
    ///   club being considered — the multiplier the AI-vs-AI market already
    ///   weights its shortlist with in `FreeAgencyEngine.simulateAIFreeAgency`,
    ///   re-expressed for an additive model. `nil` means nobody has rated this
    ///   building and returns exactly 0.
    ///
    /// **Nothing new is persisted for this.** The appeal behind it is derived
    /// from rows the tree already keeps: the staff's development attributes,
    /// blended with the `PlayerSeasonHistory` deltas of the young players who
    /// were actually on their watch (`CoachDevelopmentEngine.developerRecord`).
    /// Early in a career it is therefore a projection off attributes and later
    /// a record — which is the honest shape of a reputation anyway.
    ///
    /// The un-mapping reads `developmentAppealRange` instead of re-typing its
    /// ±0.15 half-span, so widening the band over there moves both halves of
    /// the market together rather than silently splitting them apart.
    ///
    /// **Symmetric, unlike ``fanSupportBonus(_:)``.** Every club has a staff, so
    /// a caller that ranks clubs against each other must pass this for ALL of
    /// them or for NONE — handing it to the user's bid alone would not be a
    /// reputation model, it would be a home-field bonus wearing one. The size
    /// above is set on that assumption: small enough to break a tie between two
    /// clubs, never large enough to overturn the cheque, the depth chart or the
    /// scheme that put them in a tie.
    static func developerReputationBonus(_ developmentAppeal: Double?) -> Double {
        guard let developmentAppeal else { return 0 }
        let range = CoachingEngine.developmentAppealRange
        let halfSpan = (range.upperBound - range.lowerBound) / 2.0
        guard halfSpan > 0 else { return 0 }
        let neutral = range.lowerBound + halfSpan
        let clamped = min(range.upperBound, max(range.lowerBound, developmentAppeal))
        let tilt = (clamped - neutral) / halfSpan // -1...+1
        return tilt * developerReputationSwing
    }

    // MARK: - Role

    /// How clear the player's path to a starting role is on the given roster
    /// (1.0 = walks into the lineup, ~0.15 = buried behind better players).
    static func roleScore(player: Player, teamID: UUID, allPlayers: [Player]) -> Double {
        roleScore(candidate: Candidate(player: player), teamID: teamID, allPlayers: allPlayers)
    }

    /// The role math, over a value input — see ``Candidate``.
    static func roleScore(candidate: Candidate, teamID: UUID, allPlayers: [Player]) -> Double {
        let (groupPositions, _) = FreeAgencyEngine.positionGroupInfo(for: candidate.position)
        let incumbents = allPlayers.filter {
            $0.teamID == teamID && $0.id != candidate.id && groupPositions.contains($0.position)
        }
        guard let bestIncumbent = incumbents.map(\.overall).max() else {
            return 1.0 // nobody at the position — instant starter
        }

        let diff = candidate.overall - bestIncumbent
        switch diff {
        case 3...:      return 1.0   // clear upgrade over the current best
        case (-2)...2:  return 0.7   // competes for the starting job
        case (-6)...:   return 0.4   // rotational piece
        default:        return 0.15  // buried on the depth chart
        }
    }

    /// One-line explanation of the role reading, for visit reveals.
    static func roleNote(player: Player, teamID: UUID, allPlayers: [Player]) -> String {
        let score = roleScore(player: player, teamID: teamID, allPlayers: allPlayers)
        switch score {
        case 1.0:       return "Sees a clear starting job with you"
        case 0.7:       return "Believes he can win the starting job here"
        case 0.4:       return "Worries he'd be a rotational piece for you"
        default:        return "Thinks he'd be buried on your depth chart"
        }
    }

    // MARK: - Private

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
