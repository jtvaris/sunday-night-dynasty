import Foundation

// MARK: - RosterValue

/// How much a club values keeping a player on the 53 — the cutdown-day sort
/// key (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §5 stage 6).
///
/// The AI cutdown used to be a straight `overall` sort. With phase 2's rookie
/// scaling (`DraftEngine.rookieScaleFactors`: a rookie enters at ~70-75 % of
/// his eventual level, ~59 OVR, with the ROUND signal carried entirely by his
/// ceiling) that sort cuts essentially every draft pick on sight — measured
/// over `MultiSeasonSmokeTest`, only 76 of 269 draftees held a roster spot by
/// the fifth season, the yp0-3 share of the league fell to 26 % against
/// `DEVELOPMENT_NFL_REFERENCE.md` §8's 45-55 %, and the league became a closed
/// pool of veterans that could only ratchet upward (+5.10 OVR in five seasons
/// against the plan's |Δ| ≤ 2.0 gate).
///
/// Real clubs do not cut a first-round rookie for a 70-OVR journeyman, and this
/// is the model the `career` harness has always used to reproduce
/// `DRAFT_NFL_REFERENCE.md` §6 (`CareerScenario.keepScore`). It moves nobody's
/// rating — only who gets the opportunity, which is then the R factor's
/// `opportunity` term.
enum RosterValue {

    /// Per-year value penalty once a player is past the cheap-youth age.
    static let agePenaltyPerYear = 3.2
    /// Age from which the penalty starts accruing.
    static let agePenaltyFrom = 25
    /// How much of a young player's untapped ceiling counts as present value.
    static let upsidePremium = 0.45
    /// Years of pro service over which draft capital still buys patience.
    static let patienceYears = 3

    /// Draft capital by round: clubs keep nearly every pick through year one
    /// and a first-rounder for three. Undrafted players buy none.
    static func draftCapital(round: Int?) -> Double {
        switch round ?? 8 {
        case 1:  return 13
        case 2:  return 9
        case 3:  return 6
        case 4:  return 4
        case 5:  return 2.5
        case 6:  return 2
        case 7:  return 1.5
        default: return 0
        }
    }

    /// Cutdown sort key — higher survives.
    static func keepScore(_ player: Player) -> Double {
        var score = Double(player.overall)
        // Cheap youth beats expensive age at the back of a roster.
        score -= Double(max(0, player.age - agePenaltyFrom)) * agePenaltyPerYear
        if player.yearsPro <= patienceYears {
            score += Double(max(0, player.truePotential - player.overall)) * upsidePremium
            let round = player.draftRound
                ?? player.draftPickNumber.map { ($0 - 1) / 32 + 1 }
            score += draftCapital(round: round) * (player.yearsPro <= 1 ? 1.0 : 0.45)
        }
        return score
    }
}
