import Foundation

// MARK: - ShoppingPoll
//
// F-58, the half that answers the question. "Who wants my backup tight end?"
// had no surface at all: `RosterView` has no trade affordance, `PlayerDetailView`
// offers "Trade For" on a RIVAL and nothing on one of your own, and the Trade
// Center's builder is partner-first — you must already know who to call before
// it can help you.
//
// A poll is what a GM does instead. It asks all 31 clubs the same question and
// reports who leaned in.
//
// ## Where the numbers come from
//
// `GMMarketView.incomingPlayerValue` — the engine's own function for "what is
// this man worth to THIS front office" — and nothing else. It is chart value
// times a need premium times that club's stance-driven taste in ages, which is
// exactly the three reasons a real club is or is not interested. Dividing it by
// the neutral `playerTradeValue` gives the premium over the chart, and that
// ratio is the whole ranking.
//
// Nothing here prices a PACKAGE, and that is deliberate. What a club would
// actually send back depends on its roster, its picks and a negotiation, and the
// Trade Center already runs that conversation properly. The poll's job is to
// name the phone numbers worth dialling and then hand off — every row opens the
// builder with that club selected.
//
// ## What this is NOT
//
// It is not a promise that the phone will ring. `shoppingTarget` — the function
// that decides who the AI calls the user about — does not read the user's block
// or the poll, and no copy on either surface says it does. See the note on
// `TradeBlockStore` for the exact engine seam that would change that.

/// One club's appetite for one of the user's players.
struct ShoppingInterest: Identifiable {

    let teamID: UUID
    let abbreviation: String
    let fullName: String
    /// What this club's GM prices the player at, in chart points.
    let value: Int
    /// `value` as a ratio of the neutral chart value. 1.10 = a 10 % premium.
    let premium: Double
    /// This club's need severity at the player's position, 0…1.
    let needSeverity: Double
    let stance: TradeValueEngine.TeamStance
    /// False when the user has burned this GM's patience for the league year.
    let talksOpen: Bool

    var id: UUID { teamID }

    /// The premium as a signed percentage, e.g. `"+14%"`.
    var premiumText: String {
        let points = Int(((premium - 1.0) * 100).rounded())
        return points >= 0 ? "+\(points)%" : "\(points)%"
    }

    /// Why this club leaned in, in the club's own terms.
    var reason: String {
        if !talksOpen {
            return "Not taking your calls this year."
        }
        if needSeverity >= ShoppingPoll.strongNeed {
            return "\(stance.label) \u{00B7} a hole at the position"
        }
        if needSeverity >= ShoppingPoll.someNeed {
            return "\(stance.label) \u{00B7} thin at the position"
        }
        switch stance {
        case .contend: return "Contending \u{00B7} buying proven help"
        case .retool:  return "Retooling \u{00B7} opportunistic both ways"
        case .rebuild: return "Rebuilding \u{00B7} wants picks, not veterans"
        }
    }

    /// How warm this is, for the status pill.
    var tone: DSStatusPill.Tone {
        if !talksOpen { return .bad }
        if premium >= ShoppingPoll.keenPremium { return .ok }
        if premium >= ShoppingPoll.mildPremium { return .info }
        return .neutral
    }

    var toneLabel: String {
        if !talksOpen { return "Cold" }
        if premium >= ShoppingPoll.keenPremium { return "Keen" }
        if premium >= ShoppingPoll.mildPremium { return "Interested" }
        return "Would listen"
    }
}

/// Polls the league on one of the user's players.
enum ShoppingPoll {

    /// Need severity at which a position group is a hole rather than merely
    /// thin. The same 0.30 the post-trade receipt uses for the same idea
    /// (`TradeView.holeSeverity`), so the two screens describe one league.
    static let strongNeed = 0.30
    /// Below `strongNeed` but still worth naming.
    static let someNeed = 0.15

    /// Premium above the chart at which a club reads as actively keen.
    ///
    /// `incomingPlayerValue` applies up to +28 % of need premium and the
    /// stance's age multiplier on top, so the band is set inside that range
    /// rather than at its edge: 1.10 is a club that wants him, 1.03 is a club
    /// that would take the call.
    static let keenPremium = 1.10
    static let mildPremium = 1.03

    /// Interest below this is not shown at all — a club that prices a man under
    /// the chart is not a phone number, it is noise.
    static let floorPremium = 0.90

    /// Asks all 31 rivals what they think of one of the user's players.
    ///
    /// - Returns: the interested clubs, keenest first, filtered to those above
    ///   `floorPremium`.
    static func poll(
        player: Player,
        userTeamID: UUID?,
        teams: [Team],
        allPlayers: [Player],
        season: Int,
        week: Int
    ) -> [ShoppingInterest] {
        let chart = Double(TradeValueEngine.playerTradeValue(player: player))
        guard chart > 0 else { return [] }

        // Computed once and handed to every market view. `marketView` derives it
        // per call otherwise, which is 31 passes over the whole league roster
        // for one sheet.
        let coreReference = TradeValueEngine.leagueCoreReference(allPlayers: allPlayers)

        var results: [ShoppingInterest] = []
        for team in teams where team.id != userTeamID {
            let view = TradeValueEngine.marketView(
                team: team,
                allPlayers: allPlayers,
                season: season,
                week: week,
                coreReference: coreReference
            )
            let value = view.incomingPlayerValue(player)
            let premium = value / chart
            guard premium >= floorPremium else { continue }
            results.append(
                ShoppingInterest(
                    teamID: team.id,
                    abbreviation: team.abbreviation,
                    fullName: team.fullName,
                    value: Int(value.rounded()),
                    premium: premium,
                    needSeverity: view.needs.severity(player.position),
                    stance: view.stance,
                    talksOpen: view.talksOpen
                )
            )
        }

        // A club that will not take your calls sinks to the bottom whatever it
        // thinks of the player: an unreachable premium is not an opportunity.
        return results.sorted {
            if $0.talksOpen != $1.talksOpen { return $0.talksOpen }
            if $0.premium != $1.premium { return $0.premium > $1.premium }
            return $0.abbreviation < $1.abbreviation
        }
    }

    /// One line summarising a poll, for a trade-block row.
    static func summary(_ interests: [ShoppingInterest]) -> String {
        let live = interests.filter { $0.talksOpen && $0.premium >= mildPremium }
        guard let best = live.first else {
            return "Nobody is paying over the chart for him right now."
        }
        if live.count == 1 {
            return "\(best.abbreviation) at \(best.premiumText) over the chart, and nobody else."
        }
        return "\(live.count) clubs above the chart \u{2014} \(best.abbreviation) leads at \(best.premiumText)."
    }
}
