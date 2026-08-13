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
    static func interest(
        player: Player,
        askingPrice: Int,
        offer: (salary: Int, years: Int)?,
        team: Team,
        allPlayers: [Player],
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        hostedVisit: Bool = false
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
            hostedVisit: hostedVisit
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
        hostedVisit: Bool = false
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
        total = clamp01(total + visitBonus)

        return Breakdown(
            money: money,
            teamSuccess: teamSuccess,
            role: role,
            schemeFit: schemeFit,
            visitBonus: visitBonus,
            total: total
        )
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
