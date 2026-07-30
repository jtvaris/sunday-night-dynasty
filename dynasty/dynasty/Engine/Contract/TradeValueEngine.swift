import Foundation
import SwiftData

// MARK: - Trade Value Engine (R21, Wave 2 market)
//
// Modern trade valuation on the Jimmy Johnson pick-point scale:
// - Player value = exponential OVR curve × position multiplier × positional
//   age curve (RBs age fast, QBs slow) × contract-situation multiplier
//   (cheap multi-year deal is an asset, expiring/overpaid deals discount).
// - Pick value  = Jimmy Johnson chart, future-year picks discounted 20 %/year.
//
// Wave 2 (`docs/TRADE_OVERHAUL_PLAN.md` §6) built the living market on top of
// that untouched base (plan §3: the valuation layer is NFL-grade, keep it):
// - `GMPersona` — a deterministic archetype per franchise (UUID bytes, the
//   `AgentPersona` trick) with asking premium, patience, insult threshold,
//   initiate appetite and the locked §7.1 chart lean: old-school GMs spend
//   picks at chart price, analytics GMs price draft capital ABOVE the chart and
//   refuse pick-heavy overpays. The lean is HIDDEN — the user's screens keep
//   quoting plain Jimmy Johnson points.
// - `TeamStance` — contend / retool / rebuild from record + core talent + core
//   age + cap room. Sets pick-vs-player preference ("we're 1-7, a future pick
//   is worth ×1.15 to us"), incoming-age taste and untouchables.
// - `NeedProfile` — starter-QUALITY needs (not roster counts), shared by the
//   offer builders and `respond`, and symmetric: a hole at a position makes
//   incoming help worth more AND the team's own starter there harder to buy.
// - `GMMarketView` — the one place a deal is priced from one GM's chair, with
//   the anti-exploit rules folded in (package diminishing returns, roster-spot
//   cost, hidden asking noise, rejection memory) so the Trade Center preview
//   and the executed outcome cannot disagree.
//
// Also owns:
// - The trade window rule (regular season through the Week 9 deadline + offseason).
// - AI accept / reject / counter logic (persona-thresholded, memory-aware).
// - AI-initiated offers to the user: weekly with a hazard ramp into the
//   deadline, plus the offseason windows (post-FA, pre-draft, cut days).
// - The AI-vs-AI league market pass that really moves players and picks.
// - Roster-size, salary-cap, injury and no-trade-clause validation (CapMode-aware).
enum TradeValueEngine {

    // MARK: - Trade Window

    /// Last regular-season week during which trades may be made.
    /// The phase machine tags `.tradeDeadline` at the end of this week.
    ///
    /// Wave 1 moved this from 8 to 9 to match the real NFL deadline (Tuesday
    /// after week 9, i.e. past the halfway mark of the season) — the plan's
    /// finding S2. This is the single source of truth: the Trade Center's
    /// closed-window copy and the offer-expiry text already read it.
    ///
    /// PAIRED CHANGE: `WeekAdvancer` still gates its deadline pass on a
    /// hardcoded `if week == 8`; the Wave 1 phase work replaces that literal
    /// with this constant (and stops overwriting `.tradeDeadline` on the next
    /// line). Until it does, the AI-vs-AI deadline pass fires after week 8
    /// while the window stays open through week 9 — trades remain legal, the
    /// league's own flurry just lands a week early.
    static let deadlineWeek = 9

    /// Trading is open in every offseason phase and during the regular season
    /// up to and including the Week 8 deadline. Closed for playoffs and the
    /// Pro Bowl / Super Bowl ceremony weeks.
    static func isTradeWindowOpen(phase: SeasonPhase, week: Int) -> Bool {
        switch phase {
        case .regularSeason:
            return week <= deadlineWeek
        case .tradeDeadline:
            return true
        case .playoffs, .proBowl, .superBowl:
            return false
        default:
            return true
        }
    }

    // MARK: - Player Value Curve

    /// Trade value of a player on the Jimmy Johnson point scale.
    ///
    /// A 90+ OVR star is worth several times a 75 OVR starter:
    /// the base is `32 × 1.128^(OVR − 60)` (75 → ~194 pts, 90 → ~1188 pts,
    /// 99 → ~3510 pts, i.e. above the #1 overall pick before multipliers).
    static func playerTradeValue(player: Player) -> Int {
        let base = 32.0 * pow(1.128, Double(player.overall - 60))
        let value = base
            * positionMultiplier(player.position)
            * ageMultiplier(age: player.age, position: player.position)
            * contractMultiplier(player: player)
        return max(3, Int(value))
    }

    /// Premium positions carry more trade value at the same OVR.
    static func positionMultiplier(_ position: Position) -> Double {
        switch position {
        case .QB:               return 1.3
        case .WR, .DE:          return 1.1
        case .LT, .CB, .OLB:    return 1.05
        case .DT, .RT, .MLB,
             .FS, .SS, .TE:     return 1.0
        case .LG, .RG, .C:      return 0.95
        case .RB:               return 0.85
        case .FB:               return 0.6
        case .K, .P:            return 0.5
        }
    }

    /// Positional aging curve: value declines once a player passes the
    /// position's decline age; young players carry a small upside premium.
    /// RBs fall off hard after 26 while QBs hold value into their mid-30s.
    static func ageMultiplier(age: Int, position: Position) -> Double {
        let declineStart: Int
        let declinePerYear: Double
        switch position {
        case .QB:                       declineStart = 33; declinePerYear = 0.07
        case .RB, .FB:                  declineStart = 26; declinePerYear = 0.16
        case .WR:                       declineStart = 29; declinePerYear = 0.10
        case .TE:                       declineStart = 29; declinePerYear = 0.09
        case .LT, .LG, .C, .RG, .RT:    declineStart = 30; declinePerYear = 0.07
        case .DE, .DT:                  declineStart = 29; declinePerYear = 0.09
        case .OLB, .MLB:                declineStart = 28; declinePerYear = 0.09
        case .CB:                       declineStart = 28; declinePerYear = 0.12
        case .FS, .SS:                  declineStart = 28; declinePerYear = 0.10
        case .K, .P:                    declineStart = 36; declinePerYear = 0.04
        }

        if age > declineStart {
            return max(0.3, 1.0 - Double(age - declineStart) * declinePerYear)
        }
        if age <= 24 {
            // Youth premium: upside years still ahead.
            return min(1.15, 1.0 + Double(25 - age) * 0.05)
        }
        return 1.0
    }

    /// Contract situation multiplier:
    /// - Expiring deal (≤ 1 year left) or free agent → rental discount (×0.85).
    /// - Cheap multi-year deal (salary ≤ 70 % of market, 2+ years) → premium.
    /// - Overpaid (salary ≥ 130 % of market) → discount (×0.8).
    static func contractMultiplier(player: Player) -> Double {
        guard player.teamID != nil, player.contractYearsRemaining > 0 else {
            return 0.85
        }
        let market = max(1, ContractEngine.estimateMarketValue(player: player))
        let salaryRatio = Double(player.annualSalary) / Double(market)

        var multiplier = 1.0
        if player.contractYearsRemaining <= 1 {
            multiplier *= 0.85                          // deadline rental
        } else if salaryRatio <= 0.7 {
            // Bargain deal: +5 % per remaining year, capped at +20 %.
            multiplier *= min(1.2, 1.0 + 0.05 * Double(player.contractYearsRemaining))
        }
        if salaryRatio >= 1.3 {
            multiplier *= 0.8                           // overpaid contract
        }
        return max(0.6, min(1.25, multiplier))
    }

    // MARK: - Pick Value Curve

    /// Jimmy Johnson chart value with a 20 %/year discount for future picks.
    static func pickTradeValue(pick: DraftPick, currentSeason: Int) -> Int {
        let base = PickValueChart.points(forPick: pick.pickNumber)
        let yearsOut = max(0, pick.seasonYear - currentSeason)
        let discounted = Double(base) * pow(0.8, Double(yearsOut))
        return max(1, Int(discounted))
    }

    // MARK: - GM Persona (Wave 2 — plan §6 Wave 2.3, decision §7.1)

    /// The trade archetype of one franchise's general manager.
    ///
    /// This revives `TradeEvaluator.GMPersonality`, which shipped inside the
    /// binary with ZERO call sites — the model of the fix for finding S4 was
    /// already written and dead. The archetypes are keyed on `Team.id`, so a
    /// franchise's GM behaves the same way in every session and across launches
    /// without a stored field.
    ///
    /// The locked decision §7.1: the Jimmy Johnson chart stays the game's public
    /// language (war room, Trade Center, news copy) and each GM applies a HIDDEN
    /// lean on top of it. That is what makes two teams able to WANT the same
    /// trade — the surplus both sides think they are getting is the difference
    /// between their leans, exactly like a real trade market.
    enum GMArchetype: String, CaseIterable {
        /// Trusts the chart and his scouts: draft capital is currency to spend
        /// on proven players, so he will pay chart price to move up.
        case oldSchool
        /// League-average behaviour — the control group.
        case balanced
        /// Prices draft capital ABOVE the chart and discounts pick-heavy
        /// overpays hardest; the GM who refuses to move up at JJ price.
        case analytics
        /// Chases stars, pays a premium, and works the phones constantly.
        case aggressive

        var label: String {
            switch self {
            case .oldSchool:  return "Old School"
            case .balanced:   return "Even Keel"
            case .analytics:  return "Analytics"
            case .aggressive: return "Aggressive"
            }
        }

        /// One-liner for the (Wave 3) negotiation header.
        var blurb: String {
            switch self {
            case .oldSchool:  return "Spends picks on proven players. The chart is the chart."
            case .balanced:   return "Fair value, no drama. Will talk about anyone."
            case .analytics:  return "Hoards draft capital. Will not pay to move up."
            case .aggressive: return "Chases stars and calls first. Pays for now."
            }
        }

        var symbolName: String {
            switch self {
            case .oldSchool:  return "book.closed.fill"
            case .balanced:   return "scalemass.fill"
            case .analytics:  return "chart.bar.fill"
            case .aggressive: return "bolt.fill"
            }
        }

        /// HIDDEN multiplier this GM applies to every PICK he prices — the §7.1
        /// chart lean, ±10-15 %. Below 1.0 means "picks are lottery tickets, I'd
        /// rather have the player" (so he happily ships them to move up); above
        /// 1.0 means "draft capital is undervalued by the chart" (so a pile of
        /// picks does not buy his starter).
        var pickLean: Double {
            switch self {
            case .oldSchool:  return 0.87
            case .balanced:   return 1.00
            case .analytics:  return 1.14
            case .aggressive: return 0.90
            }
        }

        /// Per-extra-asset decay in a package (finding S4's quantity exploit).
        /// The analytics GM is the one who "discounts pick-heavy overpays": his
        /// fifth asset is worth almost nothing to him.
        var packageDecay: Double {
            switch self {
            case .oldSchool:  return 0.12
            case .balanced:   return 0.15
            case .analytics:  return 0.19
            case .aggressive: return 0.13
            }
        }

        /// Opening ask as a share of what he is giving up (plan: 1.05-1.25).
        /// Wave 3's concession curve walks down from here; Wave 2 uses half of
        /// the premium as the accept bar (see `GMPersona.acceptRatio`).
        var askingPremium: Double {
            switch self {
            case .oldSchool:  return 1.16
            case .balanced:   return 1.12
            case .analytics:  return 1.20
            case .aggressive: return 1.08
            }
        }

        /// Share of the remaining gap he concedes per negotiation round.
        var concessionRate: Double {
            switch self {
            case .oldSchool:  return 0.25
            case .balanced:   return 0.35
            case .analytics:  return 0.22
            case .aggressive: return 0.45
            }
        }

        /// Patience: how many rounds/insults he tolerates before the phone
        /// stops being answered for the rest of the league year.
        var maxRounds: Int {
            switch self {
            case .oldSchool:  return 2
            case .balanced:   return 4
            case .analytics:  return 3
            case .aggressive: return 3
            }
        }

        /// Value ratio below which an offer is an insult rather than a
        /// starting point (and earns a strike in the rejection memory).
        var insultCutoff: Double {
            switch self {
            case .oldSchool:  return 0.80
            case .balanced:   return 0.76
            case .analytics:  return 0.82
            case .aggressive: return 0.70
            }
        }

        /// Relative appetite for picking up the phone first.
        var initiateWeight: Double {
            switch self {
            case .oldSchool:  return 0.90
            case .balanced:   return 1.00
            case .analytics:  return 0.85
            case .aggressive: return 1.50
            }
        }
    }

    /// One franchise's GM, derived entirely from `Team.id`.
    ///
    /// Same mechanism as `AgentPersona.forPlayer`: the roll comes from the
    /// UUID's raw bytes, never `hashValue` (Hashable's seed changes every
    /// launch, which would re-roll every GM in the league on each app start).
    /// Different byte offsets are used for the archetype, the name and the
    /// per-team jitter so the three are independent draws.
    struct GMPersona {
        let teamID: UUID
        let archetype: GMArchetype
        /// Stable GM name for negotiation/news copy (Wave 3 header).
        let name: String
        /// `archetype.askingPremium` ± up to 4 points, clamped to the plan's
        /// 1.05-1.25 band, so two old-school GMs are not interchangeable.
        let askingPremium: Double
        let concessionRate: Double
        let maxRounds: Int
        let insultCutoff: Double
        let pickLean: Double
        let packageDecay: Double
        let initiateWeight: Double

        /// The bar an offer must clear for an instant yes. Half of the opening
        /// premium: the ask is what he OPENS at, this is where he signs.
        var acceptRatio: Double { 1.0 + (askingPremium - 1.0) * 0.5 }

        /// AI teams do business with each other more readily than with the
        /// user's front office — the league-wide market would seize up if all
        /// 32 GMs demanded their full retail surplus from each other.
        var leagueAcceptRatio: Double { 1.0 + (acceptRatio - 1.0) * 0.4 }

        /// The premium he OPENS at when the other side of the phone is another
        /// club's GM rather than the user's front office.
        ///
        /// The mirror of `leagueAcceptRatio`, and the calibration pass's single
        /// biggest lever. Measured funnel, before it existed: 71 % of every
        /// package the league market assembled died on the BUYER's value bar.
        /// The arithmetic why — the payment has to cover 98 % of the ask, so with
        /// a full retail ask the buyer needs
        /// `incomingLean × sellerPickLean ≥ 1.17 × retentionLean × ownPickLean`,
        /// i.e. ~17 % of surplus out of persona/stance leans that only span
        /// ±14 %. Softened to the same 40 % of the premium the accept bar keeps,
        /// the requirement drops to ~7 % and an ordinary need premium covers it.
        ///
        /// It is also simply true: a GM squeezes the tourist, not the guy he has
        /// to call again next week. The user-facing ask (`buildBuyOffer` /
        /// `buildSellOffer`) deliberately keeps the full retail premium.
        var leagueAskingPremium: Double { 1.0 + (askingPremium - 1.0) * 0.4 }

        static func forTeam(id: UUID) -> GMPersona {
            let archetype: GMArchetype
            switch Int(uuidDice(id, byteOffset: 8) % 100) {
            case ..<26:  archetype = .oldSchool
            case ..<60:  archetype = .balanced
            case ..<80:  archetype = .analytics
            default:     archetype = .aggressive
            }

            // Jitter: −0.04 … +0.04 in 0.01 steps, from a different byte window.
            let jitter = (Double(Int(uuidDice(id, byteOffset: 3) % 9)) - 4.0) / 100.0
            let premium = min(1.25, max(1.05, archetype.askingPremium + jitter))
            let nameIndex = Int(uuidDice(id, byteOffset: 11) % UInt64(gmNamePool.count))

            return GMPersona(
                teamID: id,
                archetype: archetype,
                name: gmNamePool[nameIndex],
                askingPremium: premium,
                concessionRate: archetype.concessionRate,
                maxRounds: archetype.maxRounds,
                insultCutoff: archetype.insultCutoff,
                pickLean: archetype.pickLean,
                packageDecay: archetype.packageDecay,
                initiateWeight: archetype.initiateWeight
            )
        }
    }

    /// GM names — deliberately a different pool from `AgentPersona`'s agents so
    /// a league never has the same person on both sides of a phone call.
    private static let gmNamePool: [String] = [
        "Ray Pellman", "Ed Kowal", "Mitch Delaney", "Art Fontaine",
        "Hal Brennan", "Gus Iverson", "Roy Tanaka", "Dale Whitcomb",
        "Sid Maranville", "Curt Diaz", "Lou Sarkisian", "Wes Halloran",
        "Nate Okafor", "Bud Ferraro", "Cal Rennick", "Jim Vasquez",
        "Otis Landry", "Pete Sturdivant", "Marv Chen", "Rex Bouchard",
        "Sam Ekwueme", "Denny Kovacs", "Trey Ashford", "Vic Palumbo"
    ]

    /// Packs 8 UUID bytes (from `byteOffset`, wrapping at 16) into a `UInt64`.
    /// Copy of `AgentPersona`'s helper rather than a shared utility: that one is
    /// `private` to the contract stack, and duplicating six lines is cheaper
    /// than coupling the trade engine to the negotiation engine's internals.
    private static func uuidDice(_ id: UUID, byteOffset: Int) -> UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(bytes[(byteOffset + i) % 16])
        }
        return value
    }

    /// The GM's hidden asking noise for one calendar slot: 0.955 … 1.045.
    ///
    /// Plan §6 Wave 2.4 asks for per-GM asking noise so the accept bar cannot be
    /// solved by arithmetic, but explicitly NOT `Math.random`-style: a preview
    /// that re-rolls on every redraw would make the Trade Center's verdict
    /// flicker, and preview ≡ outcome (G7) is the whole point. So the noise is a
    /// deterministic mix of the team UUID, the season and the week — stable for
    /// as long as the offer is on the table, different next week, and different
    /// for every GM in the league.
    static func askNoise(teamID: UUID, season: Int, week: Int) -> Double {
        var x = uuidDice(teamID, byteOffset: 0)
        x ^= UInt64(bitPattern: Int64(season)) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(bitPattern: Int64(week + 1)) &* 0xBF58_476D_1CE4_E5B9
        // splitmix64 finalizer — cheap, well-distributed, no Foundation RNG.
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        let step = Double(x % 91) / 1000.0        // 0.000 … 0.090
        return 0.955 + step
    }

    // MARK: - Team Stance (Wave 2 — plan §6 Wave 2.2)

    /// Where a franchise thinks it is in its competitive cycle. Drives what it
    /// wants out of the market, not just how much.
    enum TeamStance: String {
        /// Win now: buys proven help, hoards nothing, protects its core.
        case contend
        /// One good offseason from contending: opportunistic both ways.
        case retool
        /// Selling the present for the future: wants picks, especially future ones.
        case rebuild

        var label: String {
            switch self {
            case .contend: return "Contending"
            case .retool:  return "Retooling"
            case .rebuild: return "Rebuilding"
            }
        }

        /// Blanket lean on every pick this team prices. A rebuilder wants draft
        /// capital and therefore also charges more for its own.
        var pickMultiplier: Double {
            switch self {
            case .contend: return 0.94
            case .retool:  return 1.00
            case .rebuild: return 1.08
            }
        }

        /// Extra lean on picks for a LATER league year — the plan's worked
        /// example: "we're 1-7, future picks are worth ×1.15 to us". A contender
        /// discounts them for the mirror reason: next April does not help him
        /// win this January.
        var futurePickMultiplier: Double {
            switch self {
            case .contend: return 0.88
            case .retool:  return 1.00
            case .rebuild: return 1.15
            }
        }

        /// How this team values an INCOMING player of a given age. Contenders
        /// pay for win-now veterans (§5: "buyers' acquisitions skew age ≥ 27");
        /// rebuilders only want players who will still be here.
        func incomingAgeMultiplier(age: Int) -> Double {
            switch self {
            case .contend:
                if age >= 28 { return 1.10 }
                if age >= 26 { return 1.05 }
                return 1.0
            case .retool:
                if age >= 31 { return 0.92 }
                return 1.0
            case .rebuild:
                if age >= 31 { return 0.72 }
                if age >= 28 { return 0.85 }
                if age <= 25 { return 1.10 }
                return 1.0
            }
        }

        /// How dearly this team holds a player of its OWN it is asked to send
        /// away. The mirror of `incomingAgeMultiplier`: a rebuilder's 32-year-old
        /// is available cheap, a contender's is not available at all cheap.
        func retentionAgeMultiplier(age: Int) -> Double {
            switch self {
            case .contend:
                if age >= 28 { return 1.08 }
                return 1.0
            case .retool:
                return 1.0
            case .rebuild:
                if age >= 30 { return 0.82 }
                if age >= 28 { return 0.90 }
                if age <= 24 { return 1.12 }
                return 1.0
            }
        }
    }

    /// Reads a team's stance off its record, core talent, core age and cap room.
    ///
    /// Record is the loudest signal, but it cannot be the only one: in weeks 1-2
    /// every team is 0-0, which is exactly why the old `wins - losses >= 2` gate
    /// (finding S5) produced a market that could not open until October. Last
    /// season's record covers the gap, and the talent/age/cap terms are what
    /// separate a 4-4 team with a 29-year-old core (buy) from a 4-4 team with a
    /// 24-year-old core and no cap room (sell).
    /// The OVR a top-24 core has to beat for its club to read as talented.
    ///
    /// Measured against the LEAGUE, never a constant. The 24 players a club keeps
    /// first are the top half of a 53-man roster, so their mean runs ~4.5 points
    /// above the league mean; what matters to a stance is whether a core is better
    /// or worse than everyone else's, and a hardcoded reference cannot answer that.
    /// Both failure modes are measured, one on each side of the same literal: at 76
    /// the model read 20 contenders / 10 retoolers / 1 rebuilder out of 31, and the
    /// same code against a league whose ratings had been recalibrated a point lower
    /// read 0 / 3 / 28. A self-centring reference is also what makes the market
    /// immune to the OVR drift of a long career and to any future ratings work.
    static func leagueCoreReference(allPlayers: [Player]) -> Double {
        let rostered = allPlayers.filter { $0.teamID != nil && !$0.isRetired }
        guard !rostered.isEmpty else { return 80.0 }
        let mean = Double(rostered.reduce(0) { $0 + $1.overall }) / Double(rostered.count)
        return mean + 4.5
    }

    static func stance(
        for team: Team,
        roster: [Player],
        coreReference: Double = 80.0
    ) -> TeamStance {
        var score = 0.0
        let games = team.wins + team.losses + team.ties
        var recordSignal = 0.0
        if games >= 4 {
            recordSignal = Double(team.wins - team.losses) / Double(max(1, games)) * 3.0
        } else if team.hasLastSeasonRecord {
            let played = max(1, team.lastSeasonWins + team.lastSeasonLosses)
            recordSignal = Double(team.lastSeasonWins - team.lastSeasonLosses) / Double(played) * 2.4
        }
        score += recordSignal

        // Core = the 24 players the club would keep first (`RosterValue` is the
        // same key cutdown day sorts on, so "core" means the same thing here as
        // it does on the 53-man bubble).
        let core = roster
            .filter { !$0.isRetired }
            .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
            .prefix(24)
        if !core.isEmpty {
            let avgOVR = Double(core.reduce(0) { $0 + $1.overall }) / Double(core.count)
            let avgAge = Double(core.reduce(0) { $0 + $1.age }) / Double(core.count)
            // Talent, relative to the league's own core level
            // (`leagueCoreReference`) and bounded, so the record stays the loudest
            // signal this model is documented to run on.
            score += min(0.6, max(-0.6, (avgOVR - coreReference) * 0.20))
            // An old core is urgency, and urgency points in the direction the
            // record already points: old + winning = go for it, old + losing =
            // tear it down. Multiplying by the record's sign is what keeps a
            // 2-7 veteran team out of the "contend" bucket.
            score += (avgAge - 27.0) * 0.15 * (recordSignal >= 0 ? 1.0 : -1.0)
        }
        score += Double(team.availableCap) / Double(max(1, team.salaryCap)) * 1.2

        if score >= 0.55 { return .contend }
        if score <= -0.55 { return .rebuild }
        return .retool
    }

    // MARK: - Need Model (Wave 2 — plan §6 Wave 2.5)

    /// Starter-quality need per position, 0 (set) … 1 (crisis).
    ///
    /// The old model (`DraftEngine.topTeamNeeds`) counts bodies against an ideal
    /// depth chart, so five 62-OVR corners read as "no need at CB" while a team
    /// with two elite tackles and no third reads as needy. Trades are about
    /// STARTERS, so this one grades the players who would actually take the
    /// field: the top N at the position, with missing bodies scored at
    /// replacement level.
    struct NeedProfile {
        /// Severity per position, 0…1.
        let severity: [Position: Double]
        /// Effective starter OVR per position (missing slots counted at
        /// `replacementOVR`), for copy like "current avg 63 OVR".
        let starterOVR: [Position: Int]
        /// Player IDs that are currently in a starter slot at their position.
        let starterIDs: Set<UUID>

        func severity(_ position: Position) -> Double { severity[position] ?? 0 }

        /// Positions sorted by severity, worst first.
        func topNeeds(limit: Int = 4) -> [Position] {
            severity
                .filter { $0.value > 0.12 }
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map(\.key)
        }
    }

    /// Starter slots per position in the game's base personnel (11 on offence,
    /// 4-3 nickel-ish on defence). Deliberately local to the trade engine: the
    /// UI's `PositionGradeCalculator` owns the same table for depth-chart
    /// rendering, and an engine must not reach into a SwiftUI file for it.
    static let starterSlots: [Position: Int] = [
        .QB: 1, .RB: 1, .FB: 1, .WR: 3, .TE: 1,
        .LT: 1, .LG: 1, .C: 1, .RG: 1, .RT: 1,
        .DE: 2, .DT: 2, .OLB: 2, .MLB: 1,
        .CB: 3, .FS: 1, .SS: 1,
        .K: 1, .P: 1
    ]

    /// OVR a club assumes for an empty starter slot (street free agent).
    static let replacementOVR = 58.0
    /// OVR of a starter a club stops worrying about.
    static let solidStarterOVR = 76.0

    /// Grades every position on a roster by the quality of who would start.
    static func needProfile(roster: [Player]) -> NeedProfile {
        var byPosition: [Position: [Player]] = [:]
        for player in roster where !player.isRetired {
            byPosition[player.position, default: []].append(player)
        }

        var severity: [Position: Double] = [:]
        var starterOVR: [Position: Int] = [:]
        var starterIDs: Set<UUID> = []

        for position in Position.allCases {
            let slots = starterSlots[position] ?? 1
            let ranked = (byPosition[position] ?? []).sorted { $0.overall > $1.overall }
            let starters = ranked.prefix(slots)
            for starter in starters { starterIDs.insert(starter.id) }

            var total = 0.0
            for index in 0..<slots {
                total += index < starters.count ? Double(starters[index].overall) : replacementOVR
            }
            let average = total / Double(slots)
            starterOVR[position] = Int(average.rounded())

            // 76 OVR starters are fine, 60 is a crisis; the position premium
            // (QB 1.3 … K/P 0.5) decides how loudly the hole is felt.
            let gap = max(0, solidStarterOVR - average)
            let weighted = gap / 16.0 * positionMultiplier(position)
            severity[position] = min(1.0, weighted)
        }

        return NeedProfile(severity: severity, starterOVR: starterOVR, starterIDs: starterIDs)
    }

    // MARK: - GM Market View (Wave 2 — the one pricing chair)

    /// Everything one GM brings to a phone call: his persona, his club's stance,
    /// its starter-quality needs and its roster.
    ///
    /// WHY a single type: before Wave 2 the AI's opinion of a deal lived in three
    /// places that disagreed (`respond`'s ratio test, `partnerVerdict`'s preview,
    /// each offer builder's own `guard ratio >= …`), which is how "They love it"
    /// could be followed by a rejection alert. Every Wave 2 path — preview,
    /// response, weekly offer, offseason offer, AI-vs-AI pass — prices its deal
    /// through this struct, so the numbers cannot drift apart again.
    struct GMMarketView {
        let team: Team
        let persona: GMPersona
        let stance: TeamStance
        let needs: NeedProfile
        let roster: [Player]
        let season: Int
        let week: Int

        var abbreviation: String { team.abbreviation }
        var rosterCount: Int { roster.count }

        /// Hidden per-calendar-slot asking noise (deterministic, see `askNoise`).
        var noise: Double { askNoise(teamID: team.id, season: season, week: week) }

        /// Strikes this GM has logged against the user's front office this year.
        var strikes: Int { TradeTalkRegistry.strikes(season: season, teamID: team.id) }

        /// The bar a user proposal must clear. Rejection memory bites here:
        /// every lowball makes the same GM 5 % more expensive for the rest of
        /// the league year (plan §6 Wave 2.4).
        var userAcceptBar: Double {
            persona.acceptRatio * noise * (1.0 + 0.05 * Double(strikes))
        }

        /// The bar another AI club has to clear — same noise, no memory (the
        /// registry only tracks how the user behaves).
        var leagueAcceptBar: Double { persona.leagueAcceptRatio * noise }

        /// True while this GM still answers the user's calls.
        var talksOpen: Bool { strikes < persona.maxRounds }

        func isStarter(_ player: Player) -> Bool { needs.starterIDs.contains(player.id) }

        /// Players at `position` on this roster, best first.
        func depth(at position: Position) -> [Player] {
            roster.filter { $0.position == position && !$0.isRetired }
                .sorted { $0.overall > $1.overall }
        }

        /// What an INCOMING player is worth to this GM: chart value, plus the
        /// need premium (a hole at his position is why the phone call happened),
        /// plus the stance's taste in ages.
        func incomingPlayerValue(_ player: Player) -> Double {
            var value = Double(playerTradeValue(player: player))
            value *= 1.0 + 0.28 * needs.severity(player.position)
            value *= stance.incomingAgeMultiplier(age: player.age)
            return value
        }

        /// What one of this GM's OWN players costs to pry loose.
        ///
        /// The need premium is symmetric on purpose (plan §6 Wave 2.5 / finding
        /// S4): before Wave 2, need only ever made INCOMING players cheaper, so
        /// a team desperate at CB would happily sell its only good corner.
        func outgoingPlayerValue(_ player: Player) -> Double {
            var value = Double(playerTradeValue(player: player))
            let severity = needs.severity(player.position)
            value *= 1.0 + 0.24 * severity * (isStarter(player) ? 1.0 : 0.35)
            value *= stance.retentionAgeMultiplier(age: player.age)
            return value
        }

        /// Pick value with the persona's hidden chart lean and the stance's
        /// present-vs-future preference folded in.
        func pickValue(_ pick: DraftPick) -> Double {
            var value = Double(pickTradeValue(pick: pick, currentSeason: season))
            value *= persona.pickLean
            value *= stance.pickMultiplier
            if pick.seasonYear > season { value *= stance.futurePickMultiplier }
            return value
        }

        /// Total value of one side of a deal, with package diminishing returns.
        ///
        /// Plan §6 Wave 2.4, the headline exploit: value used to be a linear sum,
        /// so four 75-OVR backups (~780 pts) bought an 85-OVR star (~650 pts)
        /// from any team, every week. Now the best asset counts fully and each
        /// further one counts less (×0.85, ×0.70, ×0.55 … at the default decay),
        /// which is also simply true — a 53-man roster has 53 spots, and the
        /// fifth-best piece in a package is not what closes a deal.
        ///
        /// Applied in BOTH directions on purpose: consolidating four pieces into
        /// one star is a real, good GM move, and it stays available. What dies is
        /// the reverse.
        func sideValue(players: [Player], picks: [DraftPick], incoming: Bool) -> Double {
            var assets: [Double] = players.map { incoming ? incomingPlayerValue($0) : outgoingPlayerValue($0) }
            assets += picks.map { pickValue($0) }
            guard !assets.isEmpty else { return 0 }
            return assets
                .sorted(by: >)
                .enumerated()
                .reduce(0.0) { total, entry in
                    let weight = max(0.20, 1.0 - persona.packageDecay * Double(entry.offset))
                    return total + entry.element * weight
                }
        }

        /// Cost of the roster spots a deal consumes (plan §6 Wave 2.4).
        /// Taking three bodies for one is not free even when the math works: the
        /// club has to cut someone, and a full roster charges more.
        func rosterSpotPenalty(incomingPlayers: Int, outgoingPlayers: Int) -> Double {
            let net = incomingPlayers - outgoingPlayers
            guard net > 0 else { return 0 }
            let crowding = rosterCount >= 70 ? 1.8 : (rosterCount >= 60 ? 1.3 : 1.0)
            return Double(net) * 26.0 * crowding      // ≈ a late 6th per body
        }

        /// Hard "not for sale" rule, with the themed rejection line.
        ///
        /// §5's user-facing promise is that GMs don't get fleeced; this is the
        /// other half of it — some players simply are not available, and the
        /// answer says why instead of quoting a number.
        func untouchableReason(_ player: Player) -> String? {
            if player.position == .QB, isStarter(player), player.overall >= 78, stance != .rebuild {
                return "\(abbreviation) aren't taking calls on their starting quarterback."
            }
            switch stance {
            case .contend:
                if player.overall >= 82 && player.age <= 27 {
                    return "\(abbreviation) hang up — \(player.lastName) is the core of a team that believes it can win now."
                }
            case .retool:
                if player.overall >= 86 && player.age <= 26 {
                    return "\(abbreviation) aren't listening on \(player.lastName). He's the one player they're building around."
                }
            case .rebuild:
                if player.overall >= 84 && player.age <= 24 {
                    return "\(abbreviation) are rebuilding around \(player.lastName) — he isn't going anywhere."
                }
            }
            return nil
        }

        /// Hard roster-integrity rule: nobody trades the last body at a position
        /// that has to line up on Sunday. Generalizes the old "never their only
        /// quarterback" special case to kickers, punters and centres.
        func lastManReason(_ player: Player) -> String? {
            guard (starterSlots[player.position] ?? 0) >= 1 else { return nil }
            let count = roster.filter { $0.position == player.position && !$0.isRetired }.count
            guard count <= 1 else { return nil }
            return "\(abbreviation) won't move their only \(player.position.rawValue)."
        }
    }

    /// Builds the market view for one team.
    ///
    /// `coreReference` is `leagueCoreReference(allPlayers:)`; callers that build
    /// many views in a row (the league market pass) compute it once and pass it in
    /// rather than paying for it 31 times.
    static func marketView(
        team: Team,
        allPlayers: [Player],
        season: Int,
        week: Int,
        coreReference: Double? = nil
    ) -> GMMarketView {
        let roster = allPlayers.filter { $0.teamID == team.id && !$0.isRetired }
        return GMMarketView(
            team: team,
            persona: GMPersona.forTeam(id: team.id),
            stance: stance(
                for: team,
                roster: roster,
                coreReference: coreReference ?? leagueCoreReference(allPlayers: allPlayers)
            ),
            needs: needProfile(roster: roster),
            roster: roster,
            season: season,
            week: week
        )
    }

    // MARK: - Rejection Memory (Wave 2 — plan §6 Wave 2.4)

    /// Remembers how the user's front office has behaved toward each GM this
    /// league year: every insulting proposal is a strike, strikes make that GM
    /// more expensive, and `persona.maxRounds` strikes end the relationship
    /// until next season.
    ///
    /// UserDefaults-backed, exactly like `NegotiationLockRegistry` — the same
    /// deliberate trade-off: this is behavioural scar tissue, not save data, and
    /// putting it on `Career` would mean a schema migration for a counter that
    /// resets every February. Keys carry the season so a stale row from an
    /// abandoned career can never lock a new one.
    enum TradeTalkRegistry {

        private static let prefix = "tradeTalkStrikes"

        private static func key(season: Int, teamID: UUID) -> String {
            "\(prefix).\(season).\(teamID.uuidString)"
        }

        static func strikes(season: Int, teamID: UUID) -> Int {
            UserDefaults.standard.integer(forKey: key(season: season, teamID: teamID))
        }

        @discardableResult
        static func addStrike(season: Int, teamID: UUID) -> Int {
            let next = strikes(season: season, teamID: teamID) + 1
            UserDefaults.standard.set(next, forKey: key(season: season, teamID: teamID))
            return next
        }

        /// Clears every stored strike. Called from `WeekAdvancer.startNewSeason`
        /// so a new league year is a clean slate (and UserDefaults does not grow
        /// a row per team per season forever).
        static func reset() {
            let stale = UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(prefix) }
            for key in stale { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    // MARK: - Proposal Valuation

    /// Total value each side of a proposal is sending, on the pick-point scale.
    /// "sending" = what the offering team gives up, "receiving" = what it gets.
    static func proposalValues(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int
    ) -> (sendingValue: Int, receivingValue: Int) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let sending =
            proposal.sendingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + playerTradeValue(player: $1) }
            +
            proposal.sendingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + pickTradeValue(pick: $1, currentSeason: currentSeason) }

        let receiving =
            proposal.receivingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + playerTradeValue(player: $1) }
            +
            proposal.receivingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + pickTradeValue(pick: $1, currentSeason: currentSeason) }

        return (sending, receiving)
    }

    // MARK: - Partner Verdict (5-step, no exact numbers)

    /// How the trade partner feels about the proposal, from their perspective.
    enum PartnerVerdict: Int, CaseIterable {
        case loveIt, likeIt, onTheFence, wantMore, hangUp

        var label: String {
            switch self {
            case .loveIt:     return "They love it"
            case .likeIt:     return "They like it"
            case .onTheFence: return "They're on the fence"
            case .wantMore:   return "They'll want more"
            case .hangUp:     return "They'll hang up"
            }
        }

        var icon: String {
            switch self {
            case .loveIt:     return "star.circle.fill"
            case .likeIt:     return "hand.thumbsup.fill"
            case .onTheFence: return "arrow.left.arrow.right.circle.fill"
            case .wantMore:   return "plus.circle.fill"
            case .hangUp:     return "phone.down.fill"
            }
        }
    }

    /// Verdict from the AI partner's own chair (persona + stance + needs).
    /// Assumes the AI team is the proposal's `receivingTeamID`.
    ///
    /// EVERY hard rule folds into the verdict so the preview the user reads
    /// equals the outcome he gets (plan §6 Wave 2.4 / G7): a no-trade-clause
    /// player, an untouchable young star, the last body at a position, or a GM
    /// who has stopped answering the phone all read `.hangUp` in the builder
    /// instead of "They love it" followed by a rejection alert.
    ///
    /// The thresholds are RELATIVE to the partner's own accept bar
    /// (`GMMarketView.userAcceptBar`, which carries the persona's premium, the
    /// hidden asking noise and the rejection memory), so `.likeIt` means "this
    /// will be accepted" for every GM in the league rather than only for the
    /// average one.
    ///
    /// `week` feeds the hidden asking noise. Callers that do not pass it get the
    /// season's week-0 draw, which is stable but identical all year — the Trade
    /// Center should pass `career.currentWeek`.
    static func partnerVerdict(
        proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int,
        contracts: [Contract] = [],
        week: Int = 0
    ) -> PartnerVerdict {
        let view = marketView(
            team: aiTeam, allPlayers: allPlayers, season: currentSeason, week: week
        )
        if hardBlocker(
            proposal: proposal, view: view, allPlayers: allPlayers, contracts: contracts
        ) != nil {
            return .hangUp
        }

        let (gives, gets) = aiPerspectiveValues(
            proposal: proposal, view: view, allPlayers: allPlayers, allPicks: allPicks
        )
        guard gives > 0 else { return gets > 0 ? .loveIt : .hangUp }
        let ratio = Double(gets) / Double(gives)
        let bar = view.userAcceptBar
        let cutoff = view.persona.insultCutoff

        if ratio >= bar * 1.18 { return .loveIt }
        if ratio >= bar { return .likeIt }
        if ratio >= (bar + cutoff) / 2 { return .onTheFence }
        if ratio >= cutoff { return .wantMore }
        return .hangUp
    }

    /// Every rule that kills a deal regardless of value, in one function.
    ///
    /// Both `partnerVerdict` and `respond` call it, which is the mechanical
    /// guarantee behind preview ≡ outcome — the two used to check different
    /// subsets (the preview knew about clauses, the response also knew about the
    /// only-QB rule) and any rule added to one of them alone reads as a bug.
    static func hardBlocker(
        proposal: TradeProposal,
        view: GMMarketView,
        allPlayers: [Player],
        contracts: [Contract],
        enforceTalkLock: Bool = true
    ) -> String? {
        if enforceTalkLock, !view.talksOpen {
            return "\(view.abbreviation) have stopped returning your calls this league year — \(view.persona.name) didn't appreciate the last few offers."
        }

        if let blocker = noTradeClauseBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: [view.team],
            contracts: contracts
        ) {
            return blocker
        }

        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id] else { continue }
            if let reason = view.untouchableReason(player) { return reason }
            if let reason = view.lastManReason(player) { return reason }
        }
        return nil
    }

    // MARK: - AI Response (accept ≥105 %, reject <90 %, else counter)

    enum AIResponse {
        case accepted
        case rejected(reason: String)
        case countered(TradeProposal, message: String)
    }

    /// Deterministic, persona-driven response so previews match outcomes.
    /// Assumes the AI team is the proposal's `receivingTeamID`.
    ///
    /// Pass `contracts` to enforce no-trade clauses; without them the clause is
    /// unreadable and the deal is priced on value alone (the pre-Wave-1
    /// behaviour, plan finding S3: the clause was negotiated, stored and never
    /// read by anything).
    ///
    /// Wave 2 replaced the single 1.05/0.90 ratio test (finding S4: "propose →
    /// counter → accept is a solved 2-tap loop") with the partner's own bar:
    /// persona premium × hidden weekly noise × rejection memory. Re-spamming the
    /// same GM with lowballs now costs 5 % a strike and, at his patience limit,
    /// the rest of the league year.
    ///
    /// `rememberLowballs: false` is for ENGINE probes (e.g. the forced-holdout
    /// package search, which asks a dozen clubs the same question in one loop) —
    /// only proposals a human actually sent should scar a relationship.
    static func respond(
        to proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int,
        contracts: [Contract] = [],
        week: Int = 0,
        rememberLowballs: Bool = true
    ) -> AIResponse {
        let view = marketView(
            team: aiTeam, allPlayers: allPlayers, season: currentSeason, week: week
        )

        // Hard rules first — clause vetoes, untouchables, the last body at a
        // position, and a GM who has stopped taking calls.
        if let blocker = hardBlocker(
            proposal: proposal, view: view, allPlayers: allPlayers, contracts: contracts,
            enforceTalkLock: rememberLowballs
        ) {
            return .rejected(reason: blocker)
        }

        let (gives, gets) = aiPerspectiveValues(
            proposal: proposal, view: view, allPlayers: allPlayers, allPicks: allPicks
        )

        guard gives > 0 || gets > 0 else {
            return .rejected(reason: "There's nothing on the table.")
        }
        guard gives > 0 else { return .accepted }   // free assets

        let ratio = Double(gets) / Double(gives)
        let bar = view.userAcceptBar
        if ratio >= bar {
            return .accepted
        }

        if ratio < view.persona.insultCutoff {
            if rememberLowballs {
                let strikes = TradeTalkRegistry.addStrike(
                    season: currentSeason, teamID: aiTeam.id
                )
                if strikes >= view.persona.maxRounds {
                    return .rejected(reason: "\(view.persona.name) has heard enough. \(view.abbreviation) are done talking trade with you this league year.")
                }
                if strikes > 1 {
                    return .rejected(reason: "\(view.abbreviation) hang up again — and \(view.persona.name) says the price just went up.")
                }
            }
            return .rejected(reason: insultReason(view: view))
        }

        // Between the insult line and the accept bar → counter-offer.
        if let counter = buildCounter(
            proposal: proposal,
            view: view,
            gives: gives,
            gets: gets,
            allPlayers: allPlayers,
            allPicks: allPicks
        ) {
            return .countered(counter.proposal, message: counter.message)
        }
        return .rejected(reason: "\(view.abbreviation) want more than you can offer right now.")
    }

    /// Persona-flavoured brush-off for an offer below the insult line.
    private static func insultReason(view: GMMarketView) -> String {
        switch view.persona.archetype {
        case .oldSchool:
            return "\(view.abbreviation) hang up — \(view.persona.name) says that isn't how the chart works."
        case .balanced:
            return "\(view.abbreviation) hang up — the offer isn't close to their asking price."
        case .analytics:
            return "\(view.abbreviation) hang up — \(view.persona.name) says the math isn't remotely there."
        case .aggressive:
            return "\(view.abbreviation) hang up — \(view.persona.name) wants a real offer, not a starting point."
        }
    }

    /// Values from the AI's own chair: its persona's chart lean, its stance's
    /// present-vs-future taste, its starter-quality needs in BOTH directions,
    /// package diminishing returns and the roster-spot cost of the bodies it
    /// would be taking on.
    private static func aiPerspectiveValues(
        proposal: TradeProposal,
        view: GMMarketView,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> (gives: Int, gets: Int) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        // The AI is the receiving team, so it GIVES the proposal's receiving
        // side and GETS the sending side.
        let givesPlayers = proposal.receivingPlayers.compactMap { playerLookup[$0] }
        let givesPicks   = proposal.receivingPicks.compactMap   { pickLookup[$0] }
        let getsPlayers  = proposal.sendingPlayers.compactMap   { playerLookup[$0] }
        let getsPicks    = proposal.sendingPicks.compactMap     { pickLookup[$0] }

        let gives = view.sideValue(players: givesPlayers, picks: givesPicks, incoming: false)
        var gets = view.sideValue(players: getsPlayers, picks: getsPicks, incoming: true)
        gets -= view.rosterSpotPenalty(
            incomingPlayers: getsPlayers.count, outgoingPlayers: givesPlayers.count
        )

        return (Int(gives.rounded()), Int(max(0, gets).rounded()))
    }

    /// Builds a counter that lands just past the partner's accept bar:
    /// 1) ask for one more of the user's picks, else
    /// 2) pull the smallest AI asset out of the deal.
    private static func buildCounter(
        proposal: TradeProposal,
        view: GMMarketView,
        gives: Int,
        gets: Int,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> (proposal: TradeProposal, message: String)? {
        let target = view.userAcceptBar + 0.02
        let deficit = Int(Double(gives) * target) - gets
        guard deficit > 0 else { return nil }

        // Option 1: request an additional pick from the offering team. Priced in
        // the AI's currency (its chart lean decides how much a 2029 third is
        // actually worth to it), which is why an analytics GM asks for fewer
        // picks than an old-school one to close the same gap.
        let offeringTeamID = proposal.offeringTeamID
        let candidatePicks = allPicks
            .filter {
                $0.currentTeamID == offeringTeamID
                    && !$0.isComplete
                    && !proposal.sendingPicks.contains($0.id)
            }
            .sorted { view.pickValue($0) < view.pickValue($1) }

        if let addition = candidatePicks.first(where: { view.pickValue($0) >= Double(deficit) }) {
            var counter = proposal
            counter.sendingPicks.append(addition.id)
            let label = "\(addition.seasonYear) round \(addition.round) pick"
            return (counter, "\(view.abbreviation) counter: add your \(label) and \(view.persona.name) signs it.")
        }

        // Option 2: AI removes its smallest outgoing asset instead.
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        var removables: [(id: UUID, isPlayer: Bool, value: Int, label: String)] = []
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id] else { continue }
            removables.append((id, true, Int(view.outgoingPlayerValue(player)), player.fullName))
        }
        for id in proposal.receivingPicks {
            guard let pick = pickLookup[id] else { continue }
            removables.append((
                id, false,
                Int(view.pickValue(pick)),
                "their \(pick.seasonYear) round \(pick.round) pick"
            ))
        }

        let viable = removables
            .filter { candidate in
                let newGives = gives - candidate.value
                guard newGives > 0 else { return false }
                return Double(gets) / Double(newGives) >= view.userAcceptBar
            }
            .sorted { $0.value < $1.value }

        if let removal = viable.first,
           removables.count > 1 {   // never counter down to an empty AI side
            var counter = proposal
            if removal.isPlayer {
                counter.receivingPlayers.removeAll { $0 == removal.id }
            } else {
                counter.receivingPicks.removeAll { $0 == removal.id }
            }
            return (counter, "\(view.abbreviation) counter: \(removal.label) stays out of the deal.")
        }

        return nil
    }

    // MARK: - Validation

    /// Returns human-readable blockers for a proposal (empty = valid).
    ///
    /// Checks, in order: no-trade clauses, injured players, roster-size bounds
    /// for both teams and — unless sandbox — that both teams stay under their
    /// salary cap after the swap, dead money included.
    ///
    /// Every rule here is symmetric on purpose (plan finding S5f / G7): the
    /// stored-offer invalidator (`isProposalStillValid`) already voided offers
    /// built on injured players, but the user's own proposals were never
    /// checked, so the builder happily shipped an injured player the AI would
    /// never have offered. Same for the clause: a rule the preview does not
    /// know about is a rule that reads as a bug.
    static func validationErrors(
        proposal: TradeProposal,
        allPlayers: [Player],
        teams: [Team],
        capMode: CapMode,
        contracts: [Contract] = [],
        /// Share of a club's salary cap it may finish the deal over. Zero — an
        /// exact fit — for everything the user can see or do; the AI-vs-AI market
        /// passes a small slack for the restructure the game does not model (see
        /// the call site in `dealIsCoherent`).
        capSlackFraction: Double = 0,
        /// Largest legal roster after the deal. In-season this is the default 75
        /// (53 active plus slack); between the draft and cutdown day the league
        /// legitimately carries 80-90 players, and applying the in-season number
        /// there vetoed 1 748 otherwise-valid deals in one measured league year —
        /// the offseason market's single biggest killer. Callers that know they
        /// are in an offseason window pass `offseasonRosterCeiling`.
        rosterCeiling: Int = 75,
        /// Smallest legal roster after the deal. The default 40 keeps an in-season
        /// squad playable; in the offseason it is simply not a rule — between the
        /// last game and free agency a club's roster legitimately falls to the
        /// low 40s or below as contracts expire, and applying 40 there stopped
        /// SELLERS from selling in exactly the windows §5 expects the most
        /// business. Offseason callers pass `offseasonRosterFloor`.
        rosterFloor: Int = 40
    ) -> [String] {
        var errors: [String] = []
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let teamLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        guard let offering = teamLookup[proposal.offeringTeamID],
              let receiving = teamLookup[proposal.receivingTeamID] else {
            return ["Unknown team in the proposal."]
        }

        let sendingPlayers = proposal.sendingPlayers.compactMap { playerLookup[$0] }
        let receivingPlayers = proposal.receivingPlayers.compactMap { playerLookup[$0] }

        // No-trade clause: a hard veto in both directions.
        if let blocker = noTradeClauseBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: teams,
            contracts: contracts
        ) {
            errors.append(blocker)
        }

        // Injured players cannot be traded — the same rule that voids a stored
        // AI offer the moment one of its assets goes down.
        for player in sendingPlayers where player.isInjured {
            errors.append("\(player.fullName) is injured — \(offering.abbreviation) can't trade him until he's cleared.")
        }
        for player in receivingPlayers where player.isInjured {
            errors.append("\(player.fullName) is injured — \(receiving.abbreviation) won't move him until he's cleared.")
        }

        // Roster-size bounds (keep both squads playable).
        let minRoster = max(0, rosterFloor)
        let maxRoster = max(minRoster + 1, rosterCeiling)
        let offeringCount = allPlayers.filter { $0.teamID == offering.id }.count
            - sendingPlayers.count + receivingPlayers.count
        let receivingCount = allPlayers.filter { $0.teamID == receiving.id }.count
            + sendingPlayers.count - receivingPlayers.count

        if offeringCount < minRoster {
            errors.append("\(offering.abbreviation) roster would drop below \(minRoster) players.")
        }
        if receivingCount < minRoster {
            errors.append("\(receiving.abbreviation) roster would drop below \(minRoster) players.")
        }
        if offeringCount > maxRoster {
            errors.append("\(offering.abbreviation) roster would exceed \(maxRoster) players.")
        }
        if receivingCount > maxRoster {
            errors.append("\(receiving.abbreviation) roster would exceed \(maxRoster) players.")
        }

        // Salary-cap check (skipped entirely in sandbox mode). Uses the same
        // dead-money split `TradeEngine.executeTrade` applies, so a deal that
        // validates here cannot push a team over the cap once executed.
        if capMode != .sandbox {
            let offeringSide = capDeltas(for: sendingPlayers, contracts: contracts, capMode: capMode)
            let receivingSide = capDeltas(for: receivingPlayers, contracts: contracts, capMode: capMode)

            let offeringUsageAfter = offering.currentCapUsage
                - offeringSide.oldHit + offeringSide.deadCap + receivingSide.assumed
            let receivingUsageAfter = receiving.currentCapUsage
                - receivingSide.oldHit + receivingSide.deadCap + offeringSide.assumed

            let slack = max(0.0, capSlackFraction)
            let offeringLimit = offering.salaryCap + Int(Double(offering.salaryCap) * slack)
            let receivingLimit = receiving.salaryCap + Int(Double(receiving.salaryCap) * slack)

            if offeringUsageAfter > offeringLimit {
                let over = offeringUsageAfter - offering.salaryCap
                errors.append("\(offering.abbreviation) would be $\(formatThousands(over)) over the cap.")
            }
            if receivingUsageAfter > receivingLimit {
                let over = receivingUsageAfter - receiving.salaryCap
                errors.append("\(receiving.abbreviation) would be $\(formatThousands(over)) over the cap.")
            }
        }

        return errors
    }

    /// Cap totals for one side of a trade: the cap hits leaving the books, the
    /// dead money staying behind, and the base salary the other team assumes.
    static func capDeltas(
        for players: [Player],
        contracts: [Contract],
        capMode: CapMode
    ) -> (oldHit: Int, deadCap: Int, assumed: Int) {
        let index = contractIndex(contracts)
        var oldHit = 0
        var deadCap = 0
        var assumed = 0
        for player in players {
            let split = CapManagementEngine.tradeCapSplit(
                player: player,
                contract: index[player.id],
                capMode: capMode
            )
            oldHit  += player.annualSalary
            deadCap += split.deadCap
            assumed += split.salaryAssumed
        }
        return (oldHit, deadCap, assumed)
    }

    /// Reason string when any player in the package carries an ACTIVE no-trade
    /// clause, otherwise `nil`.
    ///
    /// "Active" means the clause sits on the contract the player is currently
    /// playing under for his current team — a stale row from a previous deal
    /// never blocks anything. The clause was dead data before Wave 1 (finding
    /// S3): `ContractNegotiationEngine` hands it to ~50 % of 90+ OVR players
    /// who ask for it, stores it, and nothing ever read it back.
    ///
    /// `teams` only supplies the partner's abbreviation for the message; an
    /// unknown team degrades to "That team" rather than dropping the veto. The
    /// user-side message names no team on purpose, so it reads correctly from
    /// `respond`, which only knows the AI side.
    static func noTradeClauseBlocker(
        proposal: TradeProposal,
        allPlayers: [Player],
        teams: [Team],
        contracts: [Contract]
    ) -> String? {
        guard !contracts.isEmpty else { return nil }

        let index = contractIndex(contracts)
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let abbr: (UUID) -> String = { id in
            teams.first { $0.id == id }?.abbreviation ?? "That team"
        }

        func isProtected(_ player: Player) -> Bool {
            guard let contract = index[player.id] else { return false }
            return contract.noTradeClause && contract.teamID == player.teamID
        }

        for id in proposal.sendingPlayers {
            guard let player = playerLookup[id], isProtected(player) else { continue }
            return "\(player.fullName) holds a no-trade clause — he has to waive it before he can be included in any deal."
        }
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id], isProtected(player) else { continue }
            return "\(abbr(proposal.receivingTeamID)) can't move \(player.fullName) — his no-trade clause blocks any deal."
        }
        return nil
    }

    /// True when this player's current deal carries an active no-trade clause.
    /// The offer builders call it so the AI never SHOPS a protected player and
    /// never asks for one — an offer the validator would veto anyway is worse
    /// than no offer at all.
    static func hasActiveNoTradeClause(player: Player, contracts: [Contract]) -> Bool {
        guard !contracts.isEmpty else { return false }
        guard let contract = contracts.first(where: { $0.playerID == player.id }) else { return false }
        return contract.noTradeClause && contract.teamID == player.teamID
    }

    /// First contract per player, keyed by `playerID`. Contract rows are only
    /// minted for realistic-mode signings, so most players have none.
    private static func contractIndex(_ contracts: [Contract]) -> [UUID: Contract] {
        var index: [UUID: Contract] = [:]
        for contract in contracts where index[contract.playerID] == nil {
            index[contract.playerID] = contract
        }
        return index
    }

    /// A stored pending offer is still valid only while every asset is still
    /// owned by the team that is supposed to send it.
    static func isProposalStillValid(
        _ proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> Bool {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        for id in proposal.sendingPlayers {
            guard let player = playerLookup[id],
                  player.teamID == proposal.offeringTeamID, !player.isInjured else { return false }
        }
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id],
                  player.teamID == proposal.receivingTeamID else { return false }
        }
        for id in proposal.sendingPicks {
            guard let pick = pickLookup[id],
                  pick.currentTeamID == proposal.offeringTeamID, !pick.isComplete else { return false }
        }
        for id in proposal.receivingPicks {
            guard let pick = pickLookup[id],
                  pick.currentTeamID == proposal.receivingTeamID, !pick.isComplete else { return false }
        }
        return !(proposal.sendingPlayers.isEmpty && proposal.sendingPicks.isEmpty)
    }

    // MARK: - Market Windows (Wave 2 — plan §6 Wave 2.1, decision §7.2)

    /// When the market is active, and which ledger bucket its deals land in.
    ///
    /// Wave 2's volume shape (§5 / §7.2) is a calendar, not a constant: a quiet
    /// September, a ramp through October, a deadline-week flurry, then the four
    /// offseason windows real front offices actually do business in.
    enum MarketWindow: Equatable {
        /// Ordinary in-season week, 1 … `deadlineWeek - 1`.
        case week(Int)
        /// The deadline week itself — the loudest 72 hours of the league year.
        case deadline
        /// An offseason phase window (post-season retool, post-FA, pre-draft,
        /// cut days, post-draft OTAs).
        case offseason(SeasonPhase)

        /// Which `TradeRecordKind` an AI-vs-AI deal in this window is filed as,
        /// so the smoke bands can bucket in-season vs offseason volume.
        var aiLedgerKind: TradeRecordKind {
            switch self {
            case .week:      return .aiMarket
            case .deadline:  return .aiDeadline
            case .offseason: return .aiOffseason
            }
        }

        /// Phase stamped on the ledger row.
        var ledgerPhase: SeasonPhase {
            switch self {
            case .week:               return .regularSeason
            case .deadline:           return .tradeDeadline
            case .offseason(let phase): return phase
            }
        }

        var isInSeason: Bool {
            switch self {
            case .week, .deadline: return true
            case .offseason:       return false
            }
        }

        /// Short label for news/inbox copy.
        var label: String {
            switch self {
            case .week(let week):     return "Week \(week)"
            case .deadline:           return "Deadline week"
            case .offseason(let phase): return phase.displayName
            }
        }

        /// Whether the market runs at all in this window. The draft is Wave 4's
        /// business (pick swaps live in `DraftDayCoordinator`) and the playoff
        /// weeks are closed by rule.
        var isMarketWindow: Bool {
            switch self {
            case .week, .deadline:
                return true
            case .offseason(let phase):
                switch phase {
                case .reviewRoster, .freeAgency, .proDays, .rosterCuts, .otas: return true
                default: return false
                }
            }
        }
    }

    // MARK: - AI-Initiated Offers to the User

    /// A generated AI offer plus the explanation shown to the user.
    struct AIOffer {
        let proposal: TradeProposal
        let offeringTeamAbbr: String
        let subject: String
        let rationale: String
        /// Window the call came in — drives the expiry line in the inbox copy.
        let window: MarketWindow
    }

    /// Decision §7.2's offer band, as hard ceilings: the top of a band is a
    /// promise too — nobody wants 14 trade calls in one season.
    static let maxInSeasonOffers = 8
    static let maxOffseasonOffers = 5

    /// Hazard ramp for the user's phone (decision §7.2: 3-8 in-season offers,
    /// deadline-ramped, plus 2-5 offseason).
    ///
    /// The old rule was a flat 15 %/week over weeks 1-8 ≈ 1.2 attempts a season
    /// (finding S5), and both of its productive branches were dead. This ramps
    /// from a quiet September to a phone that will not stop ringing in deadline
    /// week, with two guarantees so the band cannot be missed by luck: the caps
    /// above, and a PITY floor — a season still almost silent at week 6, or an
    /// offseason with nothing by pre-draft, starts rolling at 100 %.
    ///
    /// Returns the number of independent rolls and the chance of each, so the
    /// caller (`WeekAdvancer`) owns the dice and nothing else has to know the
    /// shape of the curve.
    ///
    /// Expected in-season attempts, offers permitting: 0.22 + 0.31 + 0.40 + 0.49
    /// + 0.58 + 0.67 + 1.52 + 1.70 + 1.88 ≈ 7.8, of which ~5 land in weeks 7-9 —
    /// the back-loaded shape §5 describes.
    static func userOfferHazard(
        window: MarketWindow,
        offersSoFar: Int
    ) -> (rolls: Int, chancePercent: Int) {
        switch window {
        case .week(let week):
            guard offersSoFar < maxInSeasonOffers else { return (0, 0) }
            if week >= 6 && offersSoFar < 2 { return (1, 100) }
            let chance = min(94, 22 + 9 * max(0, week - 1))
            // From week 7 the market gets a second look at the user's roster —
            // this is the back-loaded shape §5 asks for.
            return (week >= 7 ? 2 : 1, chance)

        case .deadline:
            guard offersSoFar < maxInSeasonOffers else { return (0, 0) }
            if offersSoFar < 3 { return (2, 100) }
            return (2, 94)

        case .offseason(let phase):
            guard offersSoFar < maxOffseasonOffers else { return (0, 0) }
            // Two rolls per window, not one. There are only five offseason
            // windows and each roll can still come back empty — the league has to
            // have a club that wants one of the user's players and can pay for
            // him — so one roll a window measured 0-1 offers against §5's 2-5
            // band. The pity floors ride on top: an offseason still silent by
            // pre-draft rolls at 100 %, twice.
            switch phase {
            case .reviewRoster: return (2, 60)
            case .freeAgency:   return (2, 70)
            case .proDays:      return (2, offersSoFar < 1 ? 100 : 75)
            case .rosterCuts:   return (2, offersSoFar < 3 ? 100 : 60)
            case .otas:         return (2, offersSoFar < 2 ? 100 : 50)
            default:            return (0, 0)
            }
        }
    }

    /// Builds one AI-initiated offer targeting the user's team, or nil when no
    /// believable deal exists in this window. The caller owns the dice
    /// (`userOfferHazard`).
    ///
    /// Wave 2 replaced the record test (`wins - losses >= 2`, which in weeks 1-2
    /// matched nobody) with the stance model, so the phone can ring in September
    /// and in March:
    /// - `contend` / `retool` clubs BUY: picks (plus a filler if the picks fall
    ///   short) for a user player at a position they cannot start anybody at.
    /// - `rebuild` / `retool` clubs SELL: a veteran the user needs, for the
    ///   user's picks — future ones by preference, which is what makes the §5
    ///   "≥50 % of trades involve a future pick" band reachable at all.
    ///
    /// Quality gate (§7.2): the deal must clear the OFFERING GM's own bar (an AI
    /// does not propose something it would refuse) and must not be an insult to
    /// the user on plain chart value, so an incoming offer is always worth
    /// opening.
    ///
    /// `contracts` SHOULD be supplied: without it the generator cannot see
    /// no-trade clauses and may build an offer for a protected player the Trade
    /// Center then refuses to execute (preview ≡ outcome, plan G7).
    static func generateAIOffer(
        window: MarketWindow,
        userTeam: Team,
        allTeams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        capMode: CapMode,
        currentSeason: Int,
        week: Int,
        contracts: [Contract] = [],
        excludingTeamIDs: Set<UUID> = []
    ) -> AIOffer? {
        funnel.offerRolls += 1
        if !window.isInSeason { funnel.offerRollsOff += 1 }
        // One league-relative talent reference for every view this roll builds.
        let coreReference = leagueCoreReference(allPlayers: allPlayers)
        let userView = marketView(
            team: userTeam, allPlayers: allPlayers, season: currentSeason, week: week,
            coreReference: coreReference
        )
        if !window.isInSeason {
            let count = userView.roster.count
            let best = userView.roster.map(\.overall).max() ?? 0
            if funnel.offerUserRosterMin == 0 || count < funnel.offerUserRosterMin {
                funnel.offerUserRosterMin = count
            }
            if funnel.offerUserBestOVR == 0 || best < funnel.offerUserBestOVR {
                funnel.offerUserBestOVR = best
            }
        }

        // Weighted shuffle: an aggressive GM works the phones far more than an
        // analytics one, without ever being the only club that calls.
        //
        // Twenty clubs deep rather than twelve. Whether a given club has anything
        // to talk about is mostly a property OF THAT CLUB — its needs against the
        // user's roster, its cap room, its shopping list — so a short candidate
        // list is a hard ceiling on the phone ringing at all, and the measured
        // failure was "no club on this list wanted anybody" (`offerBuyNoTarget`
        // dominating) rather than any deal being refused. Twenty keeps the
        // weighting meaningful (a third of the league is still never called in a
        // given window) while making a silent league year much less likely.
        let candidates = allTeams
            .filter { $0.id != userTeam.id && !excludingTeamIDs.contains($0.id) }
            .map { team -> (team: Team, roll: Double) in
                let weight = GMPersona.forTeam(id: team.id).initiateWeight
                return (team, Double.random(in: 0..<1) * weight)
            }
            .sorted { $0.roll > $1.roll }
            .prefix(20)
            .map(\.team)

        for aiTeam in candidates {
            let aiView = marketView(
                team: aiTeam, allPlayers: allPlayers, season: currentSeason, week: week,
                coreReference: coreReference
            )
            let buyFirst = aiView.stance != .rebuild

            let builders: [() -> AIOffer?] = buyFirst
                ? [{ buildBuyOffer(buyer: aiView, seller: userView, allPlayers: allPlayers, allPicks: allPicks, allTeams: allTeams, capMode: capMode, contracts: contracts, window: window) },
                   { buildSellOffer(seller: aiView, buyer: userView, allPlayers: allPlayers, allPicks: allPicks, allTeams: allTeams, capMode: capMode, contracts: contracts, window: window) }]
                : [{ buildSellOffer(seller: aiView, buyer: userView, allPlayers: allPlayers, allPicks: allPicks, allTeams: allTeams, capMode: capMode, contracts: contracts, window: window) },
                   { buildBuyOffer(buyer: aiView, seller: userView, allPlayers: allPlayers, allPicks: allPicks, allTeams: allTeams, capMode: capMode, contracts: contracts, window: window) }]

            for builder in builders {
                if let offer = builder() {
                    funnel.offerBuilt += 1
                    if !window.isInSeason { funnel.offerBuiltOff += 1 }
                    return offer
                }
            }
        }
        funnel.offerNil += 1
        return nil
    }

    /// One club buys a player from another (the user, or another AI team in the
    /// league pass). Payment is picks first, one filler body if they fall short.
    private static func buildBuyOffer(
        buyer: GMMarketView,
        seller: GMMarketView,
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        contracts: [Contract],
        window: MarketWindow
    ) -> AIOffer? {
        guard let target = shoppingTarget(
            buyer: buyer, seller: seller, contracts: contracts, capMode: capMode
        ) else {
            funnel.offerBuyNoTarget += 1
            return nil
        }

        // The ask is the SELLER's price (need premium + stance retention), lifted
        // by the seller's asking premium and hidden noise — this is where the
        // "why did they want so much for him?" texture comes from.
        let ask = seller.outgoingPlayerValue(target)
            * seller.persona.askingPremium
            * seller.noise

        let buyerPicks = allPicks.filter { $0.currentTeamID == buyer.team.id && !$0.isComplete }
        // No room for the contract? Then the package opens with salary going the
        // other way, which is what makes the call possible at all.
        let needsRelief = !canAbsorbExactly(
            buyer: buyer.team, players: [target], contracts: contracts, capMode: capMode
        )
        guard let payment = buildPayment(
            payer: buyer,
            seller: seller,
            picks: buyerPicks,
            ask: ask,
            maxPicks: 3,
            allowFiller: true,
            preferFuture: seller.stance != .contend,
            contracts: contracts,
            capReliefSalary: needsRelief ? target.annualSalary : 0
        ) else {
            funnel.offerBuyPay += 1
            return nil
        }

        let proposal = TradeProposal(
            offeringTeamID: buyer.team.id,
            receivingTeamID: seller.team.id,
            sendingPlayers: payment.players.map(\.id),
            receivingPlayers: [target.id],
            sendingPicks: payment.picks.map(\.id),
            receivingPicks: []
        )

        guard dealIsCoherent(
            proposal: proposal,
            offering: buyer,
            receiving: seller,
            offeringSends: (payment.players, payment.picks),
            receivingSends: ([target], []),
            allPlayers: allPlayers,
            allPicks: allPicks,
            allTeams: allTeams,
            capMode: capMode,
            contracts: contracts,
            requireReceivingBar: false,
            rosterBounds: rosterBounds(for: window)
        ) else {
            funnel.offerBuyIncoherent += 1
            return nil
        }

        let assetText = offerAssetText(
            players: payment.players, picks: payment.picks, currentSeason: buyer.season
        )
        let motive = buyer.stance == .contend
            ? "are pushing for the playoffs"
            : "think they're a piece away"
        return AIOffer(
            proposal: proposal,
            offeringTeamAbbr: buyer.abbreviation,
            subject: "\(buyer.abbreviation) call about \(target.lastName)",
            rationale: "\(buyer.team.fullName) (\(buyer.team.record)) \(motive) and want \(target.fullName) (\(target.position.rawValue), \(target.overall) OVR) — their \(target.position.rawValue) room is starting the season's worst film. \(buyer.persona.name) is offering: \(assetText).",
            window: window
        )
    }

    /// One club shops a player of its own and asks for picks.
    private static func buildSellOffer(
        seller: GMMarketView,
        buyer: GMMarketView,
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        contracts: [Contract],
        window: MarketWindow
    ) -> AIOffer? {
        guard let vet = sellableAsset(
            seller: seller, buyer: buyer, contracts: contracts, capMode: capMode
        ) else {
            funnel.offerSellNoAsset += 1
            return nil
        }

        let ask = seller.outgoingPlayerValue(vet)
            * seller.persona.askingPremium
            * seller.noise

        let buyerPicks = allPicks.filter { $0.currentTeamID == buyer.team.id && !$0.isComplete }
        guard let payment = buildPayment(
            payer: buyer,
            seller: seller,
            picks: buyerPicks,
            ask: ask,
            maxPicks: 2,
            allowFiller: false,
            preferFuture: seller.stance != .contend,
            contracts: contracts
        ) else {
            funnel.offerSellPay += 1
            return nil
        }

        let proposal = TradeProposal(
            offeringTeamID: seller.team.id,
            receivingTeamID: buyer.team.id,
            sendingPlayers: [vet.id],
            receivingPlayers: [],
            sendingPicks: [],
            receivingPicks: payment.picks.map(\.id)
        )

        guard dealIsCoherent(
            proposal: proposal,
            offering: seller,
            receiving: buyer,
            offeringSends: ([vet], []),
            receivingSends: (payment.players, payment.picks),
            allPlayers: allPlayers,
            allPicks: allPicks,
            allTeams: allTeams,
            capMode: capMode,
            contracts: contracts,
            requireReceivingBar: false,
            rosterBounds: rosterBounds(for: window)
        ) else {
            funnel.offerSellIncoherent += 1
            return nil
        }

        let askText = offerAssetText(players: [], picks: payment.picks, currentSeason: seller.season)
        let motive = seller.stance == .rebuild
            ? "are selling — \(seller.persona.name) wants draft capital, not a .500 season"
            : "are reshaping the roster"
        return AIOffer(
            proposal: proposal,
            offeringTeamAbbr: seller.abbreviation,
            subject: "\(seller.abbreviation) shopping \(vet.lastName)",
            rationale: "\(seller.team.fullName) (\(seller.team.record)) \(motive). They're offering \(vet.position.rawValue) \(vet.fullName) (\(vet.overall) OVR, age \(vet.age)) and asking for \(askText).",
            window: window
        )
    }

    /// The best player on `seller`'s roster that `buyer` would actually call
    /// about: healthy, unprotected, and at a position `buyer` cannot start
    /// anybody at.
    ///
    /// Only used for offers aimed at the USER, and deliberately does NOT apply
    /// `untouchableReason`: "not for sale" is the user's call to make, not a
    /// filter that quietly stops his phone from ringing about his best player.
    /// The price protects him instead — the ask is his own club's retention value
    /// plus the market premium, so a package for a 27-year-old star almost never
    /// comes together, and when it does it is worth reading. `lastManReason`
    /// stays: an offer for his only kicker is not a decision, it is a bug.
    private static func shoppingTarget(
        buyer: GMMarketView,
        seller: GMMarketView,
        contracts: [Contract],
        capMode: CapMode
    ) -> Player? {
        let candidates = seller.roster.filter { player in
            guard player.overall >= 72, !player.isInjured, !player.isHoldingOut else { return false }
            guard buyer.needs.severity(player.position) >= 0.18 else { return false }
            guard seller.lastManReason(player) == nil else { return false }
            guard !hasActiveNoTradeClause(player: player, contracts: contracts) else { return false }
            return true
        }
        // Cap-affordable targets first (`canAbsorbExactly`) — a GM does not phone
        // about a player he cannot fit, and an offer the Trade Center would veto on
        // acceptance is worse than no offer at all (preview ≡ outcome, plan G7).
        // The fallback is deliberate rather than a hard filter: `buildPayment` can
        // send a salary back the other way, and that is exactly how a capped-out
        // club buys anybody. Hard-filtering here made the phone go SILENT in a
        // league year where 27 of 32 clubs were over the cap.
        let affordable = candidates.filter {
            canAbsorbExactly(
                buyer: buyer.team, players: [$0], contracts: contracts, capMode: capMode
            )
        }
        // A random one of the five most valuable fits. Five rather than three on
        // purpose: the top of the list is also the least affordable, and sampling
        // only from it means most calls die in `buildPayment` and the phone never
        // rings about the useful, actually-tradable player.
        return (affordable.isEmpty ? candidates : affordable)
            .sorted { playerTradeValue(player: $0) > playerTradeValue(player: $1) }
            .prefix(5)
            .randomElement()
    }

    /// Everyone a club is willing to move, best first. The stance decides who
    /// that is: rebuilders shop veterans and expiring deals, retoolers shop age
    /// and non-starters, contenders only sell depth they are not using.
    ///
    /// Shared by the user-facing sell offers and the AI-vs-AI league pass so the
    /// league's shopping list is one list (plan §6 Wave 2.5: the need model is
    /// shared by offers and `respond`).
    static func saleCandidates(seller: GMMarketView, contracts: [Contract]) -> [Player] {
        seller.roster
            .filter { player in
                guard !player.isInjured, !player.isHoldingOut, player.overall >= 72 else { return false }
                guard seller.untouchableReason(player) == nil,
                      seller.lastManReason(player) == nil else { return false }
                guard !hasActiveNoTradeClause(player: player, contracts: contracts) else { return false }
                switch seller.stance {
                case .rebuild:
                    // Anyone who will not be part of the next winning team.
                    return player.age >= 27 || player.contractYearsRemaining <= 1
                case .retool:
                    return player.age >= 28 || !seller.isStarter(player)
                case .contend:
                    return !seller.isStarter(player) && seller.needs.severity(player.position) < 0.25
                }
            }
            .sorted { playerTradeValue(player: $0) > playerTradeValue(player: $1) }
    }

    /// One player `seller` will shop to `buyer`, preferring a position the buyer
    /// cannot start anybody at.
    private static func sellableAsset(
        seller: GMMarketView,
        buyer: GMMarketView,
        contracts: [Contract],
        capMode: CapMode
    ) -> Player? {
        // Affordability first, for the same reason as `shoppingTarget` — and here
        // it IS the whole story: a sell offer asks for picks only
        // (`allowFiller: false`), so no salary comes back and a veteran the buyer
        // cannot fit is an offer that dies the moment it is accepted.
        let all = saleCandidates(seller: seller, contracts: contracts)
        let candidates = all.filter {
            canAbsorbExactly(
                buyer: buyer.team, players: [$0], contracts: contracts, capMode: capMode
            )
        }
        let pool = candidates.isEmpty ? all : candidates
        let fits = pool.filter { buyer.needs.severity($0.position) >= 0.18 }
        return (fits.isEmpty ? pool : fits).prefix(5).randomElement()
    }

    /// Greedy package builder in the SELLER's currency.
    ///
    /// Everything the market builds goes through here, which is why the §5
    /// "future pick in ≥50 % of trades" and "player+pick packages ≥25 %" bands
    /// are structural rather than hopeful: when the seller is not a contender the
    /// builder tries FUTURE picks first and only reaches for this year's board
    /// when the future ones cannot cover the ask.
    ///
    /// Credit is re-measured with `sideValue` after every addition, so the
    /// package-decay rule (each further asset counts less) is what decides when
    /// the package is enough — a bag of sixth-rounders never adds up to a
    /// starter no matter how many are in it.
    private static func buildPayment(
        payer: GMMarketView,
        seller: GMMarketView,
        picks: [DraftPick],
        ask: Double,
        maxPicks: Int,
        allowFiller: Bool,
        preferFuture: Bool,
        contracts: [Contract],
        /// Salary the payer has to get OFF his books for the deal to fit under his
        /// cap — the incoming player's salary when he has no room for it, zero when
        /// he does. Non-zero makes the builder open with a salary-matching player
        /// instead of only reaching for one when the picks fall short: it is how a
        /// capped-out club buys anybody in the real league, and by the third season
        /// of a career this league has almost no club with room (measured: 5-9 of
        /// 32 under the cap, and 665-3 799 candidate deals a year rejected for the
        /// buyer's cap alone).
        capReliefSalary: Int = 0,
        /// True only on the AI-vs-AI path, so `MarketFunnel`'s affordability
        /// breakdown measures the league market and is not diluted by the
        /// user-facing offer builders that share this function.
        funnelCounted: Bool = false
    ) -> (players: [Player], picks: [DraftPick])? {
        guard ask > 0 else { return nil }

        let ordered: [DraftPick]
        if preferFuture {
            let future = picks.filter { $0.seasonYear > payer.season }
                .sorted { seller.pickValue($0) > seller.pickValue($1) }
            let current = picks.filter { $0.seasonYear <= payer.season }
                .sorted { seller.pickValue($0) > seller.pickValue($1) }
            ordered = future + current
        } else {
            ordered = picks.sorted { seller.pickValue($0) > seller.pickValue($1) }
        }

        var chosenPicks: [DraftPick] = []
        var chosenPlayers: [Player] = []
        func credited() -> Double {
            seller.sideValue(players: chosenPlayers, picks: chosenPicks, incoming: true)
        }

        // Ceiling the walk has to stay under: the same 1.45× the final guard
        // enforces. Checking it per addition rather than only at the end is worth
        // a real slice of the market — 13 % of all league-market calls used to die
        // on a package whose LAST asset pushed it past the ceiling, when skipping
        // that one asset and taking the next smaller one covers the ask cleanly.
        let ceiling = ask * 1.45

        /// Everyone the payer is allowed to put in a package.
        func fillerPool() -> [Player] {
            payer.roster.filter { player in
                guard !player.isInjured, !player.isHoldingOut else { return false }
                guard player.overall >= 62, player.overall <= 82 else { return false }
                guard payer.untouchableReason(player) == nil,
                      payer.lastManReason(player) == nil else { return false }
                return !hasActiveNoTradeClause(player: player, contracts: contracts)
            }
        }

        // Cap relief goes in FIRST when the payer needs it. The player sent back
        // has to (a) carry enough salary to matter — half the incoming hit or more
        // — and (b) be small enough in value that the package can still be topped
        // up with picks without blowing the ceiling. Cheapest qualifying salary
        // wins, so the club gives up the least football it can.
        if allowFiller, capReliefSalary > 0 {
            let needed = capReliefSalary / 2
            let relief = fillerPool()
                .filter { $0.annualSalary >= needed && seller.incomingPlayerValue($0) <= ceiling }
                .min { $0.annualSalary < $1.annualSalary }
            if let relief { chosenPlayers.append(relief) }
        }

        for pick in ordered {
            if credited() >= ask { break }
            if chosenPicks.count >= maxPicks { break }
            // A first-rounder does not get thrown at a depth piece.
            if chosenPicks.isEmpty && seller.pickValue(pick) > ask * 1.4 { continue }
            chosenPicks.append(pick)
            if credited() > ceiling { chosenPicks.removeLast() }
        }

        if credited() < ask, allowFiller {
            let gap = ask - credited()
            let alreadyIn = Set(chosenPlayers.map(\.id))
            let filler = fillerPool()
                .filter { !alreadyIn.contains($0.id) }
                .min {
                    abs(seller.incomingPlayerValue($0) - gap) <
                    abs(seller.incomingPlayerValue($1) - gap)
                }
            if let filler {
                chosenPlayers.append(filler)
                if credited() > ceiling { chosenPlayers.removeLast() }
            }
        }

        guard !chosenPicks.isEmpty || !chosenPlayers.isEmpty else {
            if funnelCounted { funnel.payEmpty += 1 }
            return nil
        }
        // 2 % slack: the greedy walk lands just under the ask often enough that
        // demanding a perfect cover would kill a third of the market.
        guard credited() >= ask * 0.98 else {
            if funnelCounted { funnel.payUnder += 1 }
            return nil
        }
        // And never wildly overpay — an AI that hands over 160 % of the ask
        // reads as broken even when the user is the beneficiary.
        guard credited() <= ask * 1.45 else {
            if funnelCounted { funnel.payOver += 1 }
            return nil
        }
        return (chosenPlayers, chosenPicks)
    }

    /// Final gate every generated deal passes: the league's hard rules, both
    /// clubs' hard rules, and the value bars.
    ///
    /// `requireReceivingBar` is false for offers aimed at the USER (he is the one
    /// who decides), and true for AI-vs-AI deals where both GMs have to want it.
    /// It also selects how strict the two league-wide checks are: the
    /// chart-neutral sanity band and the cap fit are both TIGHTER for anything the
    /// user sees than for business between two AI clubs — see the comments at each
    /// of them. Nothing on the user's side of the market was loosened to make the
    /// league's volume bands reachable.
    private static func dealIsCoherent(
        proposal: TradeProposal,
        offering: GMMarketView,
        receiving: GMMarketView,
        offeringSends: (players: [Player], picks: [DraftPick]),
        receivingSends: (players: [Player], picks: [DraftPick]),
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        contracts: [Contract],
        requireReceivingBar: Bool,
        /// The window's roster bounds (`rosterBounds(for:)`) — 40-75 in-season,
        /// 28-90 in an offseason window.
        rosterBounds: (floor: Int, ceiling: Int)
    ) -> Bool {
        // Offering side must want its own proposal.
        let offeringGives = offering.sideValue(
            players: offeringSends.players, picks: offeringSends.picks, incoming: false
        )
        var offeringGets = offering.sideValue(
            players: receivingSends.players, picks: receivingSends.picks, incoming: true
        )
        offeringGets -= offering.rosterSpotPenalty(
            incomingPlayers: receivingSends.players.count,
            outgoingPlayers: offeringSends.players.count
        )
        guard offeringGives > 0, offeringGets / offeringGives >= offering.persona.leagueAcceptRatio * 0.97 else {
            if requireReceivingBar { funnel.offerBar += 1 }
            return false
        }

        if requireReceivingBar {
            let receivingGives = receiving.sideValue(
                players: receivingSends.players, picks: receivingSends.picks, incoming: false
            )
            var receivingGets = receiving.sideValue(
                players: offeringSends.players, picks: offeringSends.picks, incoming: true
            )
            receivingGets -= receiving.rosterSpotPenalty(
                incomingPlayers: offeringSends.players.count,
                outgoingPlayers: receivingSends.players.count
            )
            guard receivingGives > 0,
                  receivingGets / receivingGives >= receiving.leagueAcceptBar else {
                funnel.recvBar += 1
                return false
            }
            guard hardBlocker(
                proposal: proposal, view: receiving, allPlayers: allPlayers,
                contracts: contracts, enforceTalkLock: false
            ) == nil else {
                funnel.blocker += 1
                return false
            }
        }

        // Chart-neutral fairness: what the RECEIVING side is handed, against what
        // it gives up, in the plain Jimmy Johnson points the UI shows.
        //
        // The band is WIDER between two AI clubs than it is for anything shown to
        // the user, and that is the point of it in each case. For a user-facing
        // offer it is his protection: nobody gets phoned with an insult and
        // nobody is offered a star for a snack, so it stays at 0.82-1.45 — the
        // number the Trade Center's verdict is calibrated against.
        //
        // Between two AI clubs the JJ chart is a public language, not the rule
        // both GMs are actually pricing in: a rebuilder discounts his own
        // 30-year-old (retention ×0.82) AND marks up a future pick (stance ×1.08
        // × future ×1.15), and the product of those two leans lands the canonical
        // deadline trade — aging starter for a future mid-rounder — at a neutral
        // ratio around 1.5. The measured funnel: 91 % of the packages that
        // cleared BOTH GMs' value bars were then vetoed here, i.e. the fairness
        // band was rejecting the exact trade the market is built to produce.
        // 0.72-1.70 admits it while still refusing the absurd (a seller has to
        // recover ≥59 % of the chart value of what he ships), and both GMs' own
        // bars plus `hardBlocker` have already had their say.
        let neutralFloor = requireReceivingBar ? 0.72 : 0.82
        let neutralCeiling = requireReceivingBar ? 1.70 : 1.45
        let neutral = proposalValues(
            proposal: proposal, allPlayers: allPlayers, allPicks: allPicks,
            currentSeason: offering.season
        )
        guard neutral.receivingValue > 0 else {
            if requireReceivingBar { funnel.neutral += 1 }
            return false
        }
        let neutralRatio = Double(neutral.sendingValue) / Double(neutral.receivingValue)
        guard neutralRatio >= neutralFloor, neutralRatio <= neutralCeiling else {
            if requireReceivingBar { funnel.neutral += 1 }
            return false
        }

        let errors = validationErrors(
            proposal: proposal, allPlayers: allPlayers, teams: allTeams,
            capMode: capMode, contracts: contracts,
            // AI-vs-AI only (see `aiMarketCapSlackFraction`): the restructure the
            // game does not model. The user's own trades still have to fit under
            // the cap exactly.
            capSlackFraction: requireReceivingBar ? aiMarketCapSlackFraction : 0,
            rosterCeiling: rosterBounds.ceiling,
            rosterFloor: rosterBounds.floor
        )
        if !errors.isEmpty, requireReceivingBar {
            funnel.invalid += 1
            // Diagnostic-only classification: `validationErrors` returns display
            // strings, and the cap veto is the one the tuning pass has to be able
            // to see separately (a market that dies on cap room needs a different
            // fix from one that dies on roster bounds). Matching the sentence the
            // cap branch writes is cheap and cannot affect behaviour.
            if errors.contains(where: { $0.hasSuffix("over the cap.") }) {
                funnel.invalidCap += 1
            }
            if errors.contains(where: { $0.contains("would drop below") }) {
                funnel.invalidRosterMin += 1
            }
            if errors.contains(where: { $0.contains("would exceed") }) {
                funnel.invalidRosterMax += 1
            }
        }
        return errors.isEmpty
    }

    /// Inbox message for a freshly generated AI offer.
    static func offerInboxMessage(offer: AIOffer, week: Int, season: Int) -> InboxMessage {
        let expiry = offer.window.isInSeason
            ? "It expires at the Week \(deadlineWeek) trade deadline."
            : "It stays on the table until the market moves on."
        let dateLine = offer.window.isInSeason
            ? "Week \(week), Season \(season)"
            : "\(offer.window.label), Season \(season)"
        return InboxMessage(
            sender: .scout(name: "Pro Personnel Dept."),
            subject: offer.subject,
            body: """
            Coach,

            \(offer.rationale)

            The offer is waiting in the Trade Center — you can accept it, decline it, or use it as a starting point and negotiate. \(expiry)

            Pro Personnel
            """,
            date: dateLine,
            category: .tradeOffer,
            actionRequired: true,
            actionDestination: .trades,
            attachments: [
                MessageAttachment(title: "Open Trade Center", destination: .trades)
            ]
        )
    }

    // MARK: - AI-vs-AI League Market Pass (Wave 2 — plan §6 Wave 2.1)

    /// WHERE candidate AI-vs-AI deals die, counted across every market pass.
    ///
    /// This is the calibration instrument the §5 volume bands needed. The first
    /// tuning pass measured 5/9/3 player trades against a 30-70 band, and a raw
    /// "too few trades" number cannot say whether the cause is seller supply,
    /// affordability, a value bar or a league rule — so the pass counts every
    /// stage of the pipeline and the smoke harness prints one line per league
    /// year (`SMOKE: diag tradeFunnel …`). Turning a knob without reading it is
    /// how the market got mis-shaped in the first place.
    ///
    /// Monotonic within a league year; `MultiSeasonSmokeTest` resets it after
    /// each season's diag line. Cost is a handful of integer increments per
    /// candidate deal, so it stays on in release too — a market this hard to
    /// tune should never be un-measurable in a real career.
    struct MarketFunnel {
        /// Market passes run (one per in-season week / deadline / offseason window).
        var passes = 0
        /// Deals the windows ASKED for, split by half of the league year. The gap
        /// between this and `executed` is the market's yield — if the targets
        /// themselves are below the §5 band, no amount of yield tuning helps.
        var targetInSeason = 0
        var targetOffseason = 0
        /// Seller turns taken inside those passes.
        var turns = 0
        /// Turns where the club's stance put nobody on the shopping list.
        var noSupply = 0
        /// Sum of every shopping list's FULL length (before the per-turn cap) —
        /// divided by `turns` this is "how many players the average club is
        /// willing to move", the seller-supply number the §5 volume depends on.
        var supply = 0
        /// Stance mix, summed over every club of every pass (÷ `passes` = the
        /// league's contend/retool/rebuild split).
        var stanceContend = 0
        var stanceRetool = 0
        var stanceRebuild = 0
        /// (seller, asset) pairs actually shopped.
        var assets = 0
        /// Assets no club had a starter-quality need for.
        var noBuyer = 0
        /// (asset, buyer) calls made.
        var pairs = 0
        /// Calls where the buyer could not assemble a package for the ask.
        var payFail = 0
        /// …of which: nothing in the buyer's inventory to offer at all.
        var payEmpty = 0
        /// …of which: the best package the buyer could build fell short.
        var payUnder = 0
        /// …of which: the smallest package that covered the ask overpaid past the
        /// 1.45× ceiling (pick granularity, not unwillingness).
        var payOver = 0
        /// Packages assembled and put in front of both GMs.
        var built = 0
        /// Rejected by the SELLER's own value bar.
        var offerBar = 0
        /// Rejected by the BUYER's value bar.
        var recvBar = 0
        /// Rejected by the buyer's hard rules (untouchable / only QB / clause).
        var blocker = 0
        /// Rejected by the chart-neutral fairness band.
        var neutral = 0
        /// Rejected by league rules — cap room, roster size, no-trade clause.
        var invalid = 0
        /// …of which the binding rule was the salary cap.
        var invalidCap = 0
        /// …of which the binding rule was a roster-size bound: too few bodies
        /// left on the seller, or too many on the buyer.
        var invalidRosterMin = 0
        var invalidRosterMax = 0
        /// (asset, buyer) calls where the buyer had no cap room for the salary
        /// even with the market's restructure slack — counted, not skipped, since
        /// a filler player going the other way can still rescue the fit.
        var capTight = 0
        /// Deals executed.
        var executed = 0

        // --- The user's phone (`generateAIOffer`), same idea, separate pipeline.
        /// `generateAIOffer` calls (i.e. hazard rolls that came up).
        var offerRolls = 0
        /// …that produced no offer at all after trying up to 12 clubs.
        var offerNil = 0
        /// Buy-side (an AI club calls about one of the user's players): no player
        /// on the user's roster the club both needs and is allowed to ask about.
        var offerBuyNoTarget = 0
        /// Buy-side: the club could not assemble a package for the user's price.
        var offerBuyPay = 0
        /// Buy-side: the assembled deal failed its own bar or the fairness band.
        var offerBuyIncoherent = 0
        /// Sell-side (an AI club shops a veteran to the user): nothing on its
        /// shopping list.
        var offerSellNoAsset = 0
        /// Sell-side: the user's pick inventory could not cover the ask.
        var offerSellPay = 0
        /// Sell-side: failed the offering club's bar or the fairness band.
        var offerSellIncoherent = 0
        /// Offers that reached the user's inbox.
        var offerBuilt = 0
        /// The OFFSEASON half of `offerRolls` / `offerBuilt`. §5 bands the two
        /// halves of the league year separately (3-8 in-season + 2-5 offseason)
        /// and they fail for different reasons, so a single pair of totals cannot
        /// say which half went quiet.
        var offerRollsOff = 0
        var offerBuiltOff = 0
        /// The state of the USER's roster when an offseason call was attempted —
        /// smallest squad and weakest "best player" seen. Both are here because a
        /// silent offseason phone has two completely different causes: no club
        /// wanted anybody (a market condition), or there was nobody on the roster
        /// to want (a franchise condition, and in the harness a measurement
        /// artifact). `offerBuyNoTarget` alone cannot tell them apart.
        var offerUserRosterMin = 0
        var offerUserBestOVR = 0

        /// Second smoke line: why the user's phone did or did not ring.
        var offerSummary: String {
            "rolls=\(offerRolls)(off=\(offerRollsOff)) nil=\(offerNil) "
            + "built=\(offerBuilt)(off=\(offerBuiltOff)) "
            + "userRosterOffMin=\(offerUserRosterMin) userBestOVROff=\(offerUserBestOVR) "
            + "buy(noTarget=\(offerBuyNoTarget) pay=\(offerBuyPay) incoh=\(offerBuyIncoherent)) "
            + "sell(noAsset=\(offerSellNoAsset) pay=\(offerSellPay) incoh=\(offerSellIncoherent))"
        }

        /// One-line summary for the smoke log.
        var summary: String {
            let avgSupply = turns == 0 ? 0 : Double(supply) / Double(turns)
            let mix = passes == 0
                ? "0/0/0"
                : String(format: "%.1f/%.1f/%.1f",
                         Double(stanceContend) / Double(passes),
                         Double(stanceRetool) / Double(passes),
                         Double(stanceRebuild) / Double(passes))
            return String(format: "stance(c/r/rb)=%@ avgSupply=%.1f ", mix, avgSupply)
            + "target(in/off)=\(targetInSeason)/\(targetOffseason) "
            + "passes=\(passes) turns=\(turns) noSupply=\(noSupply) assets=\(assets) "
            + "noBuyer=\(noBuyer) pairs=\(pairs) payFail=\(payFail)"
            + "(empty=\(payEmpty) under=\(payUnder) over=\(payOver)) built=\(built) "
            + "offerBar=\(offerBar) recvBar=\(recvBar) blocker=\(blocker) "
            + "neutral=\(neutral) invalid=\(invalid)"
            + "(cap=\(invalidCap) rosterMin=\(invalidRosterMin) rosterMax=\(invalidRosterMax)) "
            + "capTight=\(capTight) executed=\(executed)"
        }
    }

    /// Live funnel counters (see `MarketFunnel`).
    static var funnel = MarketFunnel()

    /// Share of its salary cap an AI club may finish an AI-vs-AI trade over.
    ///
    /// The restructure this game does not model. A real front office absorbing a
    /// midseason addition converts base salary into signing bonus and finds the
    /// room the same afternoon; ours has no such move, and the buyer is charged
    /// the acquired player's FULL annual salary (not the remaining weeks of it,
    /// which is what the real cap charges). The two together made the cap the
    /// market's hardest wall: measured, it vetoed 1 240 of the 1 530 deals that
    /// had already cleared both GMs' value bars in season 3, and its bite GREW
    /// every year as league salary inflated.
    ///
    /// 5 % of a ~$255 M cap is ~$13 M — one good starter's salary, and inside the
    /// noise the offseason cap-growth model adds anyway. It applies ONLY to deals
    /// between two AI clubs: anything the user proposes or accepts still has to
    /// fit under the cap exactly.
    static let aiMarketCapSlackFraction = 0.05

    /// Roster ceiling the market validates against in an OFFSEASON window.
    ///
    /// Between the draft and cutdown day this league carries 80-90 players (draft
    /// class + UDFA wave, trimmed only at `rosterCuts`), which is exactly how the
    /// real offseason works — the 90-man limit is the real rule. Validating those
    /// weeks against the in-season 75 made the roster bound the offseason market's
    /// biggest single veto (1 748 deals in one measured league year, more than the
    /// cap itself), for a reason that is not a rule anywhere.
    static let offseasonRosterCeiling = 90

    /// Roster FLOOR the market validates against in an offseason window.
    ///
    /// The mirror problem, and the one that actually bit: between the last game
    /// and free agency every expiring contract empties a locker, so AI rosters
    /// spend the early offseason well under the in-season 40-man floor — and a
    /// club under the floor cannot SELL anybody, which is the side of the market
    /// those windows exist for. There is no minimum roster rule in a real March.
    static let offseasonRosterFloor = 28

    /// The bounds to validate against in this window.
    static func rosterBounds(for window: MarketWindow) -> (floor: Int, ceiling: Int) {
        window.isInSeason ? (40, 75) : (offseasonRosterFloor, offseasonRosterCeiling)
    }

    /// Whether a club has room for an AI-vs-AI acquisition, slack included.
    ///
    /// Deliberately the cheap proxy — full annual salary, no contract lookup —
    /// rather than `capDeltas`' exact split. It only ORDERS the call list (the
    /// exact math still runs in `validationErrors` before anything executes), it
    /// is asked several thousand times per market pass, and `capDeltas` rebuilds
    /// its contract index on every call. The proxy is also conservative: the real
    /// charge is the salary minus the prorated bonus, so a club this says yes to
    /// can always absorb the deal.
    static func canAbsorb(buyer: Team, salary: Int, capMode: CapMode) -> Bool {
        guard capMode != .sandbox else { return true }
        let limit = buyer.salaryCap + Int(Double(buyer.salaryCap) * aiMarketCapSlackFraction)
        return buyer.currentCapUsage + max(0, salary) <= limit
    }

    /// The same question answered EXACTLY — dead-money split included, and with no
    /// slack — for the low-frequency user-facing paths.
    ///
    /// Used to pick what a club calls the user ABOUT. A GM does not phone about a
    /// player he cannot fit under his cap, and an offer that `validationErrors`
    /// would veto on acceptance is worse than no offer at all (preview ≡ outcome,
    /// plan G7). Choosing an affordable target instead of the most expensive one
    /// is also what makes the phone ring at all in a league year where the cap is
    /// spent: measured, the third offseason of a career had 9 offer rolls produce
    /// 0 offers with 27 of 32 clubs over the cap.
    static func canAbsorbExactly(
        buyer: Team,
        players: [Player],
        contracts: [Contract],
        capMode: CapMode
    ) -> Bool {
        guard capMode != .sandbox else { return true }
        let side = capDeltas(for: players, contracts: contracts, capMode: capMode)
        return buyer.currentCapUsage + side.assumed <= buyer.salaryCap
    }

    /// Summary of an executed league trade for news/inbox rendering.
    struct LeagueTradeSummary {
        let buyerAbbr: String
        let buyerName: String
        let sellerAbbr: String
        let sellerName: String
        let playerName: String
        let playerPosition: Position
        let playerOverall: Int
        let playerID: UUID
        let buyerTeamID: UUID
        let pickDescription: String
    }

    /// Everything one market pass produced: the ledger rows (for
    /// `TradeNewsFactory.announce`) and the readable summaries (for the deadline
    /// roundup letter).
    struct LeagueMarketResult {
        var records: [TradeRecord] = []
        var summaries: [LeagueTradeSummary] = []

        var count: Int { records.count }
    }

    /// How many AI-vs-AI deals the league should try to complete in one window.
    ///
    /// This is the §5 volume band expressed as a calendar (decision §7.2), and
    /// it is deliberately front-loaded toward the deadline: September is nearly
    /// silent, weeks 5-8 pick up, and deadline week is the flurry.
    ///
    /// Expectations, if every target is met: ≈2.4 across weeks 1-6, ≈4.5 in weeks
    /// 7-8, 12-15 on deadline day (≈85 % of the in-season total in the last three
    /// weeks, comfortably above §5's 60 % floor) and ≈30 across the five offseason
    /// windows. Measured end to end over two consecutive 3-season runs: 48-53
    /// player trades a year, 17-21 of them in-season, 10-15 on deadline day, 30-32
    /// in the offseason — every §5 band, with the ceilings in `WeekAdvancer`
    /// (`maxLeagueTradesInSeason` / `maxLeagueTradesOffseason`) holding the top. The targets are
    /// deliberately set so that even a league where only HALF the attempts find a
    /// willing counterparty still lands inside every band.
    ///
    /// The weekly shape was re-cut once the market actually cleared deals: with
    /// weeks 5-6 at 0-2 the last-three-weeks share measured 57 %, i.e. September
    /// and October were doing the deadline's work. Weeks 5-6 are now 0-1 and week
    /// 8 / deadline day carry the difference — the back-loading §5 asks for is a
    /// property of the calendar, not of luck.
    ///
    /// `deficit` is the shortfall carried in from earlier windows of the same
    /// cycle: a quiet October makes deadline week louder, exactly as it does in
    /// the real league, and it is what keeps the bands reachable in a league year
    /// that happens to have few willing sellers.
    static func leagueTradeTarget(window: MarketWindow, deficit: Int = 0) -> Int {
        switch window {
        case .week(let week):
            switch week {
            case ..<3:  return Int.random(in: 1...100) <= 20 ? 1 : 0
            case 3, 4:  return Int.random(in: 0...1)
            case 5, 6:  return Int.random(in: 0...1)
            case 7:     return Int.random(in: 1...2)
            default:    return Int.random(in: 2...4)          // week 8
            }
        case .deadline:
            // FLOOR of 12, not just a range: §5 bands deadline week at 5-15 and
            // the pass converts roughly half of what it aims at once the league's
            // cap is spent, so a deadline that AIMS at 6-10 lands at 4 (measured,
            // twice). Aiming at 12-15 lands 6-8 in a tight year and is still
            // inside the band's ceiling in a loose one. The floor is what makes
            // the flurry a property of the calendar; the deficit on top is the
            // quiet-October catch-up.
            return min(15, max(12, Int.random(in: 12...15) + max(0, deficit)))
        case .offseason(let phase):
            let base: Int
            switch phase {
            // Calendar order: reviewRoster → freeAgency → proDays → (draft) →
            // otas → rosterCuts. The pre-draft window is the busiest — that is
            // when a club decides whether it is drafting a position or trading
            // for one — and cut days are the last call before kickoff.
            case .reviewRoster: base = Int.random(in: 4...7)
            case .freeAgency:   base = Int.random(in: 5...8)
            case .proDays:      base = Int.random(in: 5...9)
            case .otas:         base = Int.random(in: 4...7)
            case .rosterCuts:   base = Int.random(in: 3...5)
            default:            base = 0
            }
            guard base > 0 else { return 0 }
            return min(12, base + max(0, deficit))
        }
    }

    /// Runs the AI-vs-AI market for one window: the other 31 clubs actually
    /// trade with each other, in every phase, and every deal moves real players
    /// and picks through the same valuation, validation and ledger the user's own
    /// trades use.
    ///
    /// This is the direct answer to finding S5 ("AI-vs-AI trades exist only in
    /// the dead deadline pass — the other 31 teams never trade with each other,
    /// in any phase, ever") and its shape follows the market rather than a
    /// hardcoded contender/rebuilder split: a seller is anyone whose STANCE says
    /// he should sell, a buyer is anyone whose starter-quality NEED says he
    /// should buy, and both GMs have to clear their own bar (`dealIsCoherent`
    /// with `requireReceivingBar: true`).
    ///
    /// The user's team never participates — his roster only changes through his
    /// own decisions.
    @discardableResult
    static func runLeagueMarketPass(
        window: MarketWindow,
        targetCount: Int,
        userTeamID: UUID?,
        teams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        capMode: CapMode,
        currentSeason: Int,
        week: Int,
        modelContext: ModelContext
    ) -> LeagueMarketResult {
        var result = LeagueMarketResult()
        guard targetCount > 0 else { return result }

        let aiTeams = teams.filter { $0.id != userTeamID }
        guard aiTeams.count >= 2 else { return result }
        funnel.passes += 1
        if window.isInSeason {
            funnel.targetInSeason += targetCount
        } else {
            funnel.targetOffseason += targetCount
        }

        // Contracts are fetched once per pass (not per deal) so the market
        // enforces no-trade clauses and dead-money cap math at a fixed cost.
        let contractCareerID = WeekAdvancer.activeCareerID
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate { $0.careerID == contractCareerID }
        ))) ?? []

        // Market views are the expensive part (a need profile per team), so they
        // are built once and only the two clubs involved in a completed deal are
        // rebuilt — their rosters and cap are what just changed.
        // One league-relative talent reference for the whole pass (see
        // `leagueCoreReference`) — 31 views would otherwise each re-scan the league.
        let coreReference = leagueCoreReference(allPlayers: allPlayers)

        var views: [UUID: GMMarketView] = [:]
        for team in aiTeams {
            let view = marketView(
                team: team, allPlayers: allPlayers, season: currentSeason, week: week,
                coreReference: coreReference
            )
            views[team.id] = view
            switch view.stance {
            case .contend: funnel.stanceContend += 1
            case .retool:  funnel.stanceRetool += 1
            case .rebuild: funnel.stanceRebuild += 1
            }
        }

        // Pick inventory by club, indexed once. The candidate loop asks "what can
        // this buyer pay with?" up to a few hundred times per pass and the pool is
        // ~700 rows (7 rounds × 32 clubs × the 3-year future horizon), so filtering
        // it per candidate was the pass's whole cost.
        var picksByTeam = Dictionary(grouping: allPicks.filter { !$0.isComplete }) {
            $0.currentTeamID
        }

        // Seller order: stance first (rebuilders shop hardest), then the GM's
        // own appetite, then chance — so the same three clubs are not the whole
        // market every week. Best-motivated FIRST; the loop takes them off the
        // front (it used to `popLast()` a descending list, which handed the week
        // to the clubs least interested in selling and left the rebuilders for
        // an attempt budget that had already run out).
        func sellerOrder() -> [UUID] {
            aiTeams
                .compactMap { views[$0.id] }
                .map { view -> (id: UUID, roll: Double) in
                    let stanceWeight: Double
                    switch view.stance {
                    case .rebuild: stanceWeight = 1.6
                    case .retool:  stanceWeight = 1.1
                    case .contend: stanceWeight = 0.7
                    }
                    return (view.team.id, Double.random(in: 0..<1) * stanceWeight * view.persona.initiateWeight)
                }
                .sorted { $0.roll > $1.roll }
                .map(\.id)
        }

        var sellers = sellerOrder()
        var attempts = 0
        let attemptBudget = max(10, targetCount * 8)
        // One deal per club per pass keeps a single fire sale from being the
        // whole week's market.
        var usedTeamIDs: Set<UUID> = []

        while result.count < targetCount, attempts < attemptBudget {
            if sellers.isEmpty { sellers = sellerOrder().filter { !usedTeamIDs.contains($0) } }
            guard !sellers.isEmpty else { break }
            let sellerID = sellers.removeFirst()
            attempts += 1
            guard !usedTeamIDs.contains(sellerID), let seller = views[sellerID] else { continue }
            funnel.turns += 1

            let buyers = aiTeams
                .filter { $0.id != sellerID && !usedTeamIDs.contains($0.id) }
                .compactMap { views[$0.id] }

            guard let deal = attemptLeagueDeal(
                seller: seller,
                buyers: buyers,
                picksByTeam: picksByTeam,
                allPlayers: allPlayers,
                allPicks: allPicks,
                allTeams: teams,
                capMode: capMode,
                contracts: contracts,
                window: window,
                currentSeason: currentSeason,
                week: week,
                modelContext: modelContext
            ) else { continue }

            result.records.append(deal.record)
            result.summaries.append(deal.summary)
            usedTeamIDs.insert(sellerID)
            usedTeamIDs.insert(deal.buyerID)

            // Both clubs changed — re-read their rosters, needs and cap, and
            // re-index the picks the deal just moved.
            for id in [sellerID, deal.buyerID] {
                if let team = aiTeams.first(where: { $0.id == id }) {
                    views[id] = marketView(
                        team: team, allPlayers: allPlayers, season: currentSeason, week: week,
                        coreReference: coreReference
                    )
                }
            }
            picksByTeam = Dictionary(grouping: allPicks.filter { !$0.isComplete }) {
                $0.currentTeamID
            }
        }

        return result
    }

    /// One seller works the phones: his shopping list against every club that
    /// needs what he has. Executes the first deal both GMs sign off on.
    private static func attemptLeagueDeal(
        seller: GMMarketView,
        buyers: [GMMarketView],
        picksByTeam: [UUID: [DraftPick]],
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        contracts: [Contract],
        window: MarketWindow,
        currentSeason: Int,
        week: Int,
        modelContext: ModelContext
    ) -> (record: TradeRecord, summary: LeagueTradeSummary, buyerID: UUID)? {
        let listed = saleCandidates(seller: seller, contracts: contracts)
        funnel.supply += listed.count
        let shopping = listed.prefix(6)
        guard !shopping.isEmpty else {
            funnel.noSupply += 1
            return nil
        }

        for asset in shopping {
            funnel.assets += 1
            let ask = seller.outgoingPlayerValue(asset)
                * seller.persona.leagueAskingPremium
                * seller.noise

            let ranked = buyers
                .filter { $0.needs.severity(asset.position) >= 0.18 }
                .sorted { lhs, rhs in
                    let lhsScore = lhs.needs.severity(asset.position) * (lhs.stance == .contend ? 1.3 : 1.0)
                    let rhsScore = rhs.needs.severity(asset.position) * (rhs.stance == .contend ? 1.3 : 1.0)
                    return lhsScore > rhsScore
                }
            // Clubs that can absorb the salary today go to the front of the call
            // list. The cap is a hard league rule (`validationErrors` vetoes the
            // deal outright), so phoning a capped-out club first only burns the
            // pass's attempt budget — it was the last gate in the funnel and it
            // killed 70 % of everything that reached it. Clubs that cannot absorb
            // it are still called, last: a filler player going the other way
            // takes salary off their books and can rescue the fit.
            var fits: [GMMarketView] = []
            var tight: [GMMarketView] = []
            for buyer in ranked {
                if canAbsorb(buyer: buyer.team, salary: asset.annualSalary, capMode: capMode) {
                    fits.append(buyer)
                } else {
                    tight.append(buyer)
                }
            }
            funnel.capTight += tight.count
            let interested = (fits + tight).prefix(5)
            if interested.isEmpty { funnel.noBuyer += 1 }

            for buyer in interested {
                funnel.pairs += 1
                let buyerPicks = picksByTeam[buyer.team.id] ?? []
                let needsRelief = !canAbsorb(
                    buyer: buyer.team, salary: asset.annualSalary, capMode: capMode
                )
                guard let payment = buildPayment(
                    payer: buyer,
                    seller: seller,
                    picks: buyerPicks,
                    ask: ask,
                    maxPicks: 3,
                    allowFiller: true,
                    preferFuture: seller.stance != .contend,
                    contracts: contracts,
                    capReliefSalary: needsRelief ? asset.annualSalary : 0,
                    funnelCounted: true
                ) else {
                    funnel.payFail += 1
                    continue
                }
                funnel.built += 1

                let proposal = TradeProposal(
                    offeringTeamID: seller.team.id,
                    receivingTeamID: buyer.team.id,
                    sendingPlayers: [asset.id],
                    receivingPlayers: payment.players.map(\.id),
                    sendingPicks: [],
                    receivingPicks: payment.picks.map(\.id)
                )

                guard dealIsCoherent(
                    proposal: proposal,
                    offering: seller,
                    receiving: buyer,
                    offeringSends: ([asset], []),
                    receivingSends: (payment.players, payment.picks),
                    allPlayers: allPlayers,
                    allPicks: allPicks,
                    allTeams: allTeams,
                    capMode: capMode,
                    contracts: contracts,
                    requireReceivingBar: true,
                    rosterBounds: rosterBounds(for: window)
                ) else { continue }

                let returnText = offerAssetText(
                    players: payment.players, picks: payment.picks, currentSeason: currentSeason
                )
                let outcome = TradeEngine.executeTrade(
                    proposal: proposal,
                    allPlayers: allPlayers,
                    allPicks: allPicks,
                    capMode: capMode,
                    ledger: TradeLedger.Context(
                        kind: window.aiLedgerKind,
                        season: currentSeason,
                        week: week,
                        phase: window.ledgerPhase
                    ),
                    modelContext: modelContext
                )
                guard let record = outcome.record else { continue }

                let summary = LeagueTradeSummary(
                    buyerAbbr: buyer.abbreviation,
                    buyerName: buyer.team.fullName,
                    sellerAbbr: seller.abbreviation,
                    sellerName: seller.team.fullName,
                    playerName: asset.fullName,
                    playerPosition: asset.position,
                    playerOverall: asset.overall,
                    playerID: asset.id,
                    buyerTeamID: buyer.team.id,
                    pickDescription: returnText
                )
                funnel.executed += 1
                return (record, summary, buyer.team.id)
            }
        }
        return nil
    }

    /// League-office inbox roundup of deadline day.
    ///
    /// The per-deal HEADLINE is no longer written here: every executed trade in
    /// the league — this pass included — is announced through
    /// `TradeNewsFactory.announce`, so the news feed has one voice and one
    /// format for AI-vs-AI deals, the user's own, and draft-day swaps (the
    /// user's Wave 2 requirement: nothing moves in this league without the
    /// player being told). This letter is the league office's summary on top of
    /// those headlines, capped so a 12-deal deadline does not produce a wall of
    /// text.
    static func deadlineRoundupMessage(
        trades: [LeagueTradeSummary],
        week: Int,
        season: Int
    ) -> InboxMessage {
        let shown = trades.prefix(8)
        var lines = shown
            .map { "• \($0.buyerAbbr) acquire \($0.playerPosition.rawValue) \($0.playerName) from \($0.sellerAbbr) for \($0.pickDescription)" }
            .joined(separator: "\n")
        if trades.count > shown.count {
            lines += "\n• …and \(trades.count - shown.count) more"
        }
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Trade Deadline Day: \(trades.count) deals across the league",
            body: """
            The trade deadline has passed. Official transactions:

            \(lines)

            All trades are final. The trade window reopens in the offseason.

            NFL League Office
            """,
            date: "Week \(week), Season \(season)",
            category: .leagueNotice,
            actionDestination: .news
        )
    }

    // MARK: - Forced Trade (holdout capitulation)

    /// A ready-to-execute package for shipping one specific player out.
    struct ForcedTradePackage {
        let proposal: TradeProposal
        let partner: Team
        /// "a 2027 round 2 pick and CB Ray Voss (72 OVR)" — for inbox/news copy.
        let returnDescription: String
    }

    /// Prices a fair return for a player the front office has decided to move
    /// and picks the best-fit partner for him.
    ///
    /// Used by `HoldoutEngine.forceTrade`, which used to mark a holdout
    /// `.traded` while the player stayed on the roster (plan finding S3). The
    /// return is deliberately aimed slightly BELOW the player's market value
    /// (0.85–1.0×): a team trading a disgruntled star under duress does not get
    /// full price, and the discount is what makes an AI GM say yes.
    ///
    /// Partner order is best-fit first: teams with a top-4 positional need,
    /// then the rest, so the player lands somewhere he would actually start.
    /// Every candidate package is run through `validationErrors` AND `respond`
    /// before it is offered, so the caller can execute the returned proposal
    /// without re-asking — preview ≡ outcome (plan G7).
    ///
    /// Returns `nil` when no partner can put together a believable package
    /// (e.g. no tradable picks exist yet — finding S1); the caller must treat
    /// that as "no market" and leave the roster alone.
    static func buildForcedTradePackage(
        player: Player,
        sellingTeam: Team,
        allTeams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        contracts: [Contract],
        capMode: CapMode,
        currentSeason: Int
    ) -> ForcedTradePackage? {
        guard player.teamID == sellingTeam.id else { return nil }

        let value = playerTradeValue(player: player)
        guard value > 0 else { return nil }

        // Best-fit first: does the buyer have a top-4 need at his position?
        let candidates = allTeams
            .filter { $0.id != sellingTeam.id }
            .map { team -> (team: Team, needsHim: Bool) in
                let roster = allPlayers.filter { $0.teamID == team.id }
                let needs = Set(DraftEngine.topTeamNeeds(roster: roster, limit: 4))
                return (team, needs.contains(player.position))
            }
            .sorted { lhs, rhs in
                if lhs.needsHim != rhs.needsHim { return lhs.needsHim }
                return lhs.team.availableCap > rhs.team.availableCap
            }

        for candidate in candidates {
            let buyer = candidate.team
            let buyerRoster = allPlayers.filter { $0.teamID == buyer.id }

            // Picks first, best-first, capped at 3 — a holdout return is picks
            // and a young body, not a franchise-altering haul.
            let goal = Int(Double(value) * 0.95)
            var returnPicks: [DraftPick] = []
            var returnValue = 0
            let buyerPicks = allPicks
                .filter { $0.currentTeamID == buyer.id && !$0.isComplete }
                .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) >
                          pickTradeValue(pick: $1, currentSeason: currentSeason) }
            for pick in buyerPicks {
                guard returnValue < goal, returnPicks.count < 3 else { break }
                let pickValue = pickTradeValue(pick: pick, currentSeason: currentSeason)
                if returnValue == 0 && Double(pickValue) > Double(value) * 1.1 { continue }
                returnPicks.append(pick)
                returnValue += pickValue
            }

            // Young player to close the gap when the picks fall short.
            var returnPlayers: [Player] = []
            if returnValue < Int(Double(value) * 0.85) {
                let gap = Int(Double(value) * 0.95) - returnValue
                let filler = buyerRoster
                    .filter {
                        !$0.isInjured && $0.position != .QB
                            && $0.overall >= 60 && $0.overall <= 80
                            && !hasActiveNoTradeClause(player: $0, contracts: contracts)
                    }
                    .min { abs(playerTradeValue(player: $0) - gap) < abs(playerTradeValue(player: $1) - gap) }
                if let filler {
                    returnPlayers.append(filler)
                    returnValue += playerTradeValue(player: filler)
                }
            }

            guard returnValue > 0 else { continue }
            let ratio = Double(returnValue) / Double(value)
            guard ratio >= 0.6 && ratio <= 1.0 else { continue }

            let proposal = TradeProposal(
                offeringTeamID: sellingTeam.id,
                receivingTeamID: buyer.id,
                sendingPlayers: [player.id],
                receivingPlayers: returnPlayers.map(\.id),
                sendingPicks: [],
                receivingPicks: returnPicks.map(\.id)
            )

            guard validationErrors(
                proposal: proposal, allPlayers: allPlayers, teams: allTeams,
                capMode: capMode, contracts: contracts
            ).isEmpty else { continue }

            // `rememberLowballs: false`: this loop asks up to 31 clubs the same
            // question in one pass, and a rejection here is the ENGINE shopping a
            // holdout — not the user lowballing anyone. Letting it write strikes
            // would lock the whole league out of the Trade Center for a move the
            // user never made.
            guard case .accepted = respond(
                to: proposal, aiTeam: buyer, allPlayers: allPlayers,
                allPicks: allPicks, currentSeason: currentSeason, contracts: contracts,
                rememberLowballs: false
            ) else { continue }

            return ForcedTradePackage(
                proposal: proposal,
                partner: buyer,
                returnDescription: offerAssetText(
                    players: returnPlayers, picks: returnPicks, currentSeason: currentSeason
                )
            )
        }

        return nil
    }

    // MARK: - Helpers

    /// "a 2026 round 1 pick, a 2027 round 3 pick and WR John Smith"
    private static func offerAssetText(
        players: [Player],
        picks: [DraftPick],
        currentSeason: Int
    ) -> String {
        var parts: [String] = picks.map { "a \($0.seasonYear) round \($0.round) pick" }
        parts.append(contentsOf: players.map { "\($0.position.rawValue) \($0.fullName) (\($0.overall) OVR)" })
        guard !parts.isEmpty else { return "nothing" }
        if parts.count == 1 { return parts[0] }
        let head = parts.dropLast().joined(separator: ", ")
        return "\(head) and \(parts.last!)"
    }

    private static func formatThousands(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        return millions >= 1.0 ? String(format: "%.1fM", millions) : "\(thousands)K"
    }
}
