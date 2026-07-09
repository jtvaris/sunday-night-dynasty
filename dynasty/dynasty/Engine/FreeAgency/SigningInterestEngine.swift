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
        let role = roleScore(player: player, teamID: team.id, allPlayers: allPlayers)

        // Scheme fit when the staff runs a known scheme.
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

        // Motivation-shifted weights (money, success, role, scheme).
        let weights: (money: Double, success: Double, role: Double, scheme: Double)
        switch player.personality.motivation {
        case .money:   weights = (0.60, 0.10, 0.15, 0.15)
        case .winning: weights = (0.35, 0.35, 0.15, 0.15)
        case .stats:   weights = (0.35, 0.10, 0.35, 0.20)
        case .loyalty: weights = (0.45, 0.15, 0.20, 0.20)
        case .fame:    weights = (0.50, 0.20, 0.15, 0.15)
        }

        var total = money * weights.money
            + teamSuccess * weights.success
            + role * weights.role
            + (scheme ?? 0.5) * weights.scheme

        let visitBonus = hostedVisit ? 0.12 : 0.0
        total = clamp01(total + visitBonus)

        return Breakdown(
            money: money,
            teamSuccess: teamSuccess,
            role: role,
            schemeFit: scheme,
            visitBonus: visitBonus,
            total: total
        )
    }

    // MARK: - Role

    /// How clear the player's path to a starting role is on the given roster
    /// (1.0 = walks into the lineup, ~0.15 = buried behind better players).
    static func roleScore(player: Player, teamID: UUID, allPlayers: [Player]) -> Double {
        let (groupPositions, _) = FreeAgencyEngine.positionGroupInfo(for: player.position)
        let incumbents = allPlayers.filter {
            $0.teamID == teamID && $0.id != player.id && groupPositions.contains($0.position)
        }
        guard let bestIncumbent = incumbents.map(\.overall).max() else {
            return 1.0 // nobody at the position — instant starter
        }

        let diff = player.overall - bestIncumbent
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
