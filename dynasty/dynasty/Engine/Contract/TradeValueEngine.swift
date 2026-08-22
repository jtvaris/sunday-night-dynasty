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
    /// All-Star / Championship ceremony weeks.
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
            * injuryMultiplier(player: player)
        return max(3, Int(value))
    }

    /// Discount on a man who cannot play yet (F-54).
    ///
    /// Replaces a flat VETO. Trading an injured player is routine real business
    /// — that is what a failed-physical clause is for — and the blanket rule
    /// removed roughly 7 % of the league from the market at any moment for no
    /// modelled reason, in exactly the weeks (the deadline) when a hurt starter
    /// is the reason a club is on the phone at all.
    ///
    /// Trades against: keeping hurt men in the market versus handing the user a
    /// free arbitrage. The dependency the queue names is real and is now met —
    /// injured players no longer dress, so a discounted star is genuinely
    /// unavailable for the weeks he is out rather than a full-price starter at a
    /// markdown. The curve is linear in weeks and floors at 0.55 rather than
    /// going to zero, because a man out for the season still has next season and
    /// a contract, which is precisely what a rebuilding club is buying.
    ///
    /// 1 week ×0.96 · 4 weeks ×0.84 · 8 weeks ×0.68 · 12+ weeks ×0.55.
    static func injuryMultiplier(player: Player) -> Double {
        guard player.isInjured else { return 1.0 }
        let weeks = Double(max(1, min(12, player.injuryWeeksRemaining)))
        return max(0.55, 1.0 - 0.0375 * weeks)
    }

    /// How long a man can be out and still be somebody an AI club builds a
    /// phone call AROUND (F-54).
    ///
    /// This is taste, not law: `validationErrors` will execute a deal for a man
    /// out for the season if the user builds one, and the discount prices it.
    /// What this gates is whether a front office picks up the phone about him
    /// unprompted, and six weeks is the honest line — inside it he is back for
    /// the run-in, outside it a contender is buying next season and would rather
    /// have the pick. Trades against: market inventory versus calls the user
    /// reads as absurd ("they want to give us a man who is out until March").
    static let shoppableInjuryWeeks = 6

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
    ///
    /// `salaryCap` is the **one remaining defaulted cap in the engine layer**
    /// (task #87 / F5). It is a helper three levels inside the trade-value curve,
    /// reached from fifteen call sites that have no `Team` in hand, and the value
    /// it feeds is a RATIO (`salary ÷ market`) — so the cap cancels almost
    /// exactly and a stale one moves a multiplier by fractions of a percent
    /// rather than mispricing a contract. Every top-level market entry point
    /// takes the cap as a required argument.
    static func contractMultiplier(player: Player, salaryCap: Int = ContractEngine.openingSalaryCap) -> Double {
        guard player.teamID != nil, player.contractYearsRemaining > 0 else {
            return 0.85
        }
        let market = max(1, ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap))
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

    /// Per-year discount applied to a pick in a LATER league year (F-10).
    ///
    /// Trades against: how cheap the currency AI clubs pay with is, versus how
    /// alive the future-pick market stays. The §5 volume bands lean on future
    /// picks (a measured 100 % of five league years' AI-vs-AI deals returned
    /// nothing but them), so gutting them empties the market — but at the
    /// shipped ×0.8 the game was 1.5-1.9× too generous against every published
    /// reference. Massey-Thaler's implied rate is ~×0.42/yr and the
    /// practitioner "one full round down" rule is ×0.45-0.55; ×0.6 is the point
    /// that lands inside the practitioner band without emptying the market.
    ///
    /// The decisive number is what a REBUILDER pays. At ×0.8 his stance
    /// multipliers cancelled the discount outright — `0.8 × 1.15 × 1.08 = 0.99`,
    /// so a rebuilding club valued a 2028 second at **99 % of a 2027 second**
    /// where the real market values it at roughly half. At ×0.6 the same product
    /// is 0.745, which is a real preference for the future rather than a no-op,
    /// and that is why `TeamStance.futurePickMultiplier` can stay at 1.15
    /// instead of being cut alongside it.
    static let futurePickDiscountPerYear = 0.6

    /// Jimmy Johnson chart value with `futurePickDiscountPerYear` compounding
    /// for each league year the pick is out.
    ///
    /// Prices through `PickValueChart.value`, not `points`: after F-09 the tail
    /// steps in 0.4s and rounding it before the discount would flatten round 6
    /// back into ties. The result is rounded rather than truncated for the same
    /// reason — truncation is a systematic markdown that falls hardest on
    /// exactly the small picks F-09 exists to make usable.
    static func pickTradeValue(pick: DraftPick, currentSeason: Int) -> Int {
        let base = PickValueChart.value(forPick: pick.pickNumber)
        let yearsOut = max(0, pick.seasonYear - currentSeason)
        let discounted = base * pow(futurePickDiscountPerYear, Double(yearsOut))
        return max(1, Int(discounted.rounded()))
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

        /// TOTAL share of the opening-to-floor gap this GM will hand back for
        /// nothing but talk (task #36 anti-exploit cap).
        ///
        /// `concessionRate` alone is a geometric walk that CONVERGES on the
        /// floor: measured before this existed, a balanced GM had given back
        /// 98 % of his gap by round 10 and an aggressive one 100 %, so a user who
        /// re-sent the same package often enough talked every persona in the
        /// league down to its walk-away number at zero cost. The premium the
        /// negotiation header advertises ("opens ~16 % above value") was
        /// therefore a lie with a stopwatch on it.
        ///
        /// This is the share he concedes with NO leverage against him. Real
        /// pressure — the deadline closing, a hole he needs this player to fill
        /// — lifts the ceiling (`concessionCeiling`), and his patience caps even
        /// that. Each value is set BELOW its archetype's patience-limited walk
        /// (`1 − (1 − rate)^maxRounds` = 0.44 / 0.82 / 0.53 / 0.83) so the cap is
        /// what binds a pressure-free conversation and leverage is what unbinds
        /// it.
        var concessionCap: Double {
            switch self {
            case .oldSchool:  return 0.35
            case .balanced:   return 0.55
            case .analytics:  return 0.40
            case .aggressive: return 0.65
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
        var askingPremium: Double
        let concessionRate: Double
        /// `GMArchetype.concessionCap` — the pressure-free ceiling on the total
        /// concession a conversation can extract (task #36).
        let concessionCap: Double
        let maxRounds: Int
        let insultCutoff: Double
        var pickLean: Double
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

        /// `declaredIdentity` is F-56's seam: when a front office has DECLARED
        /// what it is (only the user's can, today), the declaration replaces the
        /// UUID draw as the archetype while the per-club jitter and the GM's
        /// name still come from the club id — so two clubs that declare the same
        /// identity are still not interchangeable. `nil` is every AI club and
        /// every career started before the picker existed, and it reproduces the
        /// old behaviour exactly.
        static func forTeam(id: UUID, declaredIdentity: FranchiseIdentity? = nil) -> GMPersona {
            let archetype: GMArchetype
            if let declaredIdentity {
                archetype = declaredIdentity.archetype
            } else {
                switch Int(uuidDice(id, byteOffset: 8) % 100) {
                case ..<26:  archetype = .oldSchool
                case ..<60:  archetype = .balanced
                case ..<80:  archetype = .analytics
                default:     archetype = .aggressive
                }
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
                concessionCap: archetype.concessionCap,
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


    // MARK: - D7-A — the scouting dossier (valuation fog)

    /// One organisation's accumulated read on ONE person in another
    /// organisation, filled in by contact and by nothing else.
    ///
    /// # Why this exists (design ruling D7, option C, part A)
    ///
    /// Until this landed, every club in the league evaluated trades against
    /// **shared truth about the other 31 organisations**. An AI club knew
    /// exactly what a rival's GM valued — his hidden chart lean, his opening
    /// premium — so a negotiation resolved to an arithmetic comparison rather
    /// than a read on a person. D3's refinement names the missing property
    /// first: *the AI lives in fog too, and not only about players*.
    ///
    /// # The shape: one dossier per (observer → person), two disciplines
    ///
    /// The record is keyed on the **person**, not the club. A GM or a head coach
    /// who moves takes his file with him and a club that hires a new one resets
    /// to unknown, which is what makes the coaching carousel matter to the user
    /// — and it is free only if the key is right from the start, which is why it
    /// is right from the start.
    ///
    /// Each dossier carries two disciplines, filled by two kinds of contact:
    ///
    /// | discipline | what it knows | what fills it | status |
    /// |---|---|---|---|
    /// | `.frontOffice` | what that GM VALUES — his hidden chart lean and his opening premium | negotiating with him | **live (D7-A)** |
    /// | `.sideline` | how that coach BEHAVES — his tendencies | playing him | **seam only (D7-B)** |
    ///
    /// The consequence the design is after falls out of the mechanism instead of
    /// being special-cased: a divisional opponent is met twice a season and is
    /// read clearly, while a cross-conference club is met once every four years
    /// and stays foggy. That is why divisional games feel different in reality.
    ///
    /// # Storage
    ///
    /// One career-scoped `UserDefaults` dictionary, the same deliberate
    /// trade-off `TradeTalkRegistry` and `TradeRequestRegistry` already make:
    /// this is accumulated organisational scar tissue, not roster state, and
    /// putting it on `Career` would mean a schema migration for a counter.
    /// Reads are memoised behind a generation counter because the league market
    /// pass prices several hundred club pairs in one advance and a
    /// `UserDefaults.dictionary` call per pair is the pass's whole cost.
    ///
    /// **Known gap, deliberately left:** the key base is not on
    /// `CareerScopedDefaults.keys`, so deleting a save does not purge it — the
    /// same gap `tradeRequestSeasons` and `tradeTalkStrikes` already have. Adding
    /// the base there is a one-line follow-up in a file this wave does not own.
    enum ScoutingDossier {

        /// Which half of an organisation a dossier line is about.
        enum Discipline: String {
            /// The general manager: what he values, what he opens at. **Live.**
            case frontOffice
            /// The head coach: what he calls, when he goes for it. **D7-B.**
            case sideline
        }

        /// The person a dossier line is about. Keyed on the man, so he takes his
        /// file with him when he changes clubs.
        struct Subject: Hashable {
            let discipline: Discipline
            let personID: UUID
        }

        /// The GM of a franchise, as a dossier subject.
        static func generalManager(_ personID: UUID) -> Subject {
            Subject(discipline: .frontOffice, personID: personID)
        }

        /// The head coach of a franchise, as a dossier subject.
        ///
        /// **D7-B SEAM — nothing calls this yet, and that is deliberate.** The
        /// gameday wave attaches here: call `recordContact` once per played game
        /// with the opposing head coach's `Coach.id`, then read `confidence` to
        /// decide how much of that coach's tendencies (fourth-down appetite,
        /// run/pass lean, blitz rate) the observing club is allowed to see. The
        /// storage, the confidence curve, the person-keying and the reset are
        /// already here and already shared with the front-office half; the
        /// tendency model itself is what has to be designed, and the ruling is
        /// explicit that it is not to be started without one.
        ///
        /// The pairing rule is satisfied the same way the front-office half
        /// satisfies it: the user's own dossier is displayed to him, and the
        /// clubs he plays accumulate the mirror record on his coach.
        static func headCoach(_ personID: UUID) -> Subject {
            Subject(discipline: .sideline, personID: personID)
        }

        /// How many separate contacts `observer` has had with `subject`.
        static func contacts(observer: UUID, subject: Subject) -> Int {
            table()[key(observer: observer, subject: subject)] ?? 0
        }

        /// Logs one contact. Negotiating with a club is a front-office contact;
        /// playing one is a sideline contact (D7-B).
        static func recordContact(observer: UUID, subject: Subject) {
            var t = table()
            let k = key(observer: observer, subject: subject)
            t[k] = (t[k] ?? 0) + 1
            write(t)
        }

        /// Logs the contact in BOTH directions. A phone call teaches both front
        /// offices something, which is the property that keeps the user inside
        /// the model rather than outside it.
        static func recordMutualContact(_ a: UUID, _ b: UUID, discipline: Discipline) {
            recordContact(
                observer: a,
                subject: Subject(discipline: discipline, personID: personID(forTeam: b))
            )
            recordContact(
                observer: b,
                subject: Subject(discipline: discipline, personID: personID(forTeam: a))
            )
        }

        /// 0 (never met him) … 1 (knows exactly what he wants).
        ///
        /// `1 − decay^contacts`, so the first meeting teaches the most and the
        /// tenth teaches almost nothing — which is how learning a person
        /// actually goes, and it is what makes a divisional rival (two contacts
        /// a season) legible inside one year while a cross-conference club stays
        /// a stranger.
        static func confidence(observer: UUID, subject: Subject) -> Double {
            let n = contacts(observer: observer, subject: subject)
            guard n > 0 else { return 0 }
            return 1.0 - pow(confidenceDecayPerContact, Double(n))
        }

        /// Share of the remaining unknown that ONE contact removes.
        ///
        /// Trades against: how long a GM stays a stranger versus how quickly the
        /// fog stops mattering at all. At 0.72 the confidence ladder runs
        /// 0 → 0.28 → 0.48 → 0.63 → 0.73 → 0.80, so a club the user has traded
        /// with twice is read to within about half the initial error and one he
        /// has never called is priced blind. Rejected: 0.5, which made a single
        /// trade wipe out most of the fog and turned the whole model into a
        /// first-deal formality.
        static let confidenceDecayPerContact = 0.72

        /// Clears every dossier line. Called from nothing today on purpose — a
        /// read on a person is not a per-season counter and must survive the
        /// league-year rollover that resets `TradeTalkRegistry`. It exists for
        /// the career-switch and save-deletion paths to reach when the key base
        /// joins `CareerScopedDefaults.keys`.
        static func reset() {
            UserDefaults.standard.removeObject(forKey: scopedKey)
            generation &+= 1
        }

        /// The dossier subject id for the GM of a franchise.
        ///
        /// **The single seam for GM turnover.** A general manager is not an
        /// entity in this game yet — `GMPersona` is derived from `Team.id` and
        /// never changes — so today the person id is a deterministic remix of
        /// the club's id. It is a REMIX rather than the club id itself so that
        /// nothing downstream can quietly conflate "this club" with "the man who
        /// runs it": when GMs become entities and start moving, this function
        /// returns his own id and every dossier line follows him without another
        /// line changing anywhere.
        static func personID(forTeam teamID: UUID) -> UUID {
            let raw = teamID.uuid
            let source = [raw.0, raw.1, raw.2, raw.3, raw.4, raw.5, raw.6, raw.7,
                          raw.8, raw.9, raw.10, raw.11, raw.12, raw.13, raw.14, raw.15]
            // Fixed salt: any constant works, it only has to be stable across
            // launches and different from the club's own id.
            let salt: [UInt8] = [0x47, 0x4D, 0x2D, 0x44, 0x37, 0x41, 0x21, 0x00,
                                 0x9E, 0x37, 0x79, 0xB9, 0x7F, 0x4A, 0x7C, 0x15]
            var bytes = [UInt8](repeating: 0, count: 16)
            for index in 0..<16 { bytes[index] = source[index] ^ salt[index] }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                               bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11],
                               bytes[12], bytes[13], bytes[14], bytes[15]))
        }

        // MARK: Storage

        private static let defaultsKey = "scoutingDossierContacts"
        private static var scopedKey: String { CareerScopedDefaults.scopedKey(defaultsKey) }

        private static func key(observer: UUID, subject: Subject) -> String {
            "\(observer.uuidString)|\(subject.discipline.rawValue)|\(subject.personID.uuidString)"
        }

        /// Memoised copy of the stored table plus the generation it was read at.
        /// The league market pass asks this question a few hundred times per
        /// advance; a `UserDefaults` round trip per question is measurable.
        private nonisolated(unsafe) static var cache: [String: Int]?
        private nonisolated(unsafe) static var cacheGeneration: UInt64 = 0
        private nonisolated(unsafe) static var generation: UInt64 = 0
        private nonisolated(unsafe) static var cacheScope: String = ""

        private static func table() -> [String: Int] {
            let scope = scopedKey
            if let cache, cacheGeneration == generation, cacheScope == scope { return cache }
            let loaded = UserDefaults.standard.dictionary(forKey: scope) as? [String: Int] ?? [:]
            cache = loaded
            cacheGeneration = generation
            cacheScope = scope
            return loaded
        }

        private static func write(_ table: [String: Int]) {
            UserDefaults.standard.set(table, forKey: scopedKey)
            cache = table
            cacheScope = scopedKey
            generation &+= 1
            cacheGeneration = generation
        }
    }

    // MARK: - F-56 — the franchise identity the user declares

    /// The identity a user declares for his own front office at career creation.
    ///
    /// D7's ruling on F-56: the user does not have a hidden persona drawn from
    /// his club's UUID — he **picks** one, and that declaration is the object the
    /// other 31 clubs form a read on. Two consequences the ruling makes
    /// mandatory, and both are built here rather than in the picker:
    ///
    /// 1. **The declaration is a PRIOR, not a fact.** It seeds what the league
    ///    believes about him; `TradeReputationRegistry` corrects it from what he
    ///    actually does. Declare yourself a value hunter, then outbid the market
    ///    twice, and the league prices you as a spender — otherwise the choice is
    ///    a free disguise, and a costless disguise is exactly the kind of
    ///    advantage D1 exists to remove.
    /// 2. **No identity may be strictly best.** Each buys something and costs
    ///    something, the way the AI archetypes already do. The three levers are
    ///    `askingPremium` (what he can charge for his own men — higher is better
    ///    for him), `pickLean` (how generously the league credits the picks it
    ///    sends him — higher is WORSE for him, because a club that respects his
    ///    picks needs fewer of them to meet his ask) and `contactAppetite` (how
    ///    often the phone rings at all). They point in different directions
    ///    inside the four archetypes, so the choice is a trade rather than a
    ///    ladder: `analytics` charges the most and is called the least,
    ///    `aggressive` charges the least and is called the most, and `oldSchool`
    ///    charges well while having his own picks discounted.
    ///
    /// **The seam.** The picker UI is another agent's. Until it exists,
    /// `FranchiseIdentityRegistry.identity(for:)` returns `nil` and every caller
    /// falls back to today's UUID draw, so behaviour is unchanged. When the
    /// picker ships it calls `set(_:for:)` once at career creation and nothing
    /// else in the market layer changes.
    enum FranchiseIdentity: String, CaseIterable {
        case oldSchool
        case balanced
        case analytics
        case aggressive

        /// The GM archetype this declaration seeds. One-to-one today because the
        /// four archetypes already span the market's levers; a fifth identity
        /// would map onto the nearest archetype rather than needing a fifth set
        /// of constants.
        var archetype: GMArchetype {
            switch self {
            case .oldSchool:  return .oldSchool
            case .balanced:   return .balanced
            case .analytics:  return .analytics
            case .aggressive: return .aggressive
            }
        }

        var label: String { archetype.label }

        /// What declaring this identity says to the league, in the user's own
        /// words. Shown at the picker and quoted back in the Trade Center.
        var declaration: String {
            switch self {
            case .oldSchool:
                return "We trust our board. Picks are currency and we spend them on football players."
            case .balanced:
                return "Fair value, both ways. We'll talk about anyone and we don't play games."
            case .analytics:
                return "Draft capital is undervalued. We charge retail for our own men and never pay to move up."
            case .aggressive:
                return "We call first and we call often. If the man wins us games, we pay for him."
            }
        }

        /// How hard the rest of the league works the phones on this front
        /// office, before reputation moves it.
        ///
        /// Trades against: how many calls a declared identity buys, against how
        /// good each one is. It is the paired COST that stops a high asking
        /// premium from being free — a club known to charge retail gets phoned
        /// less, which is the ordinary way a reputation for being expensive
        /// works. Bounded at ±15 % so no identity can miss §5's 3-8 in-season
        /// offer band on its own; the pity floors sit underneath it untouched.
        var contactAppetite: Double {
            switch self {
            case .oldSchool:  return 1.00
            case .balanced:   return 1.05
            case .analytics:  return 0.88
            case .aggressive: return 1.15
            }
        }
    }

    /// Where the user's declared identity is stored until the picker owns it.
    ///
    /// Career-scoped `UserDefaults`, one row, same trade-off as every other
    /// registry in this file. If the picker's owner would rather this were a
    /// stored `Career` field, the move is confined to these two function bodies
    /// — nothing else in the market layer reads the store directly.
    enum FranchiseIdentityRegistry {
        private static let defaultsKey = "franchiseIdentity"
        private static var scopedKey: String { CareerScopedDefaults.scopedKey(defaultsKey) }

        /// The declared identity for a club, or `nil` when nobody declared one
        /// (every AI club, and any career started before the picker existed).
        static func identity(for teamID: UUID) -> FranchiseIdentity? {
            guard let table = UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: String],
                  let raw = table[teamID.uuidString] else { return nil }
            return FranchiseIdentity(rawValue: raw)
        }

        /// Records the declaration. Called once, at career creation.
        static func set(_ identity: FranchiseIdentity, for teamID: UUID) {
            var table = UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: String] ?? [:]
            table[teamID.uuidString] = identity.rawValue
            UserDefaults.standard.set(table, forKey: scopedKey)
        }

        static func reset() {
            UserDefaults.standard.removeObject(forKey: scopedKey)
        }
    }

    // MARK: - D7-A — reputation: what the league learns from what you DO

    /// The league's running read on one front office's actual behaviour.
    ///
    /// This is the half of D7-A that makes a **reputation** possible rather than
    /// merely making offers noisy, and it is what stops F-56's declared identity
    /// from being a costless disguise. Two signals, both from things the league
    /// can actually observe:
    ///
    /// * **`lean`** — an exponentially-weighted mean of the chart ratio
    ///   (points received ÷ points sent) of his executed trades. Above 1 he
    ///   extracts surplus; below 1 he overpays. Both extremes cost him, which is
    ///   the point: a GM known to fleece people stops getting calls, and a GM
    ///   known to overpay gets plenty of calls at a worse price.
    /// * **`lowballs`** — insulting proposals he has sent anyone. This is D1's
    ///   replacement for the REJECTED per-week trade cap (F-08): a real GM is not
    ///   limited by a rule, he is limited by counterparties who stop taking his
    ///   calls. `TradeTalkRegistry` already ends one relationship at that GM's
    ///   patience limit; this is the part that leaks across the league, so
    ///   working through all 31 clubs with lowballs prices the 31st call worse
    ///   than the first instead of costing nothing at all.
    ///
    /// **Only the user's club is recorded, and that is principled rather than
    /// lazy.** An AI club's archetype *is* its behaviour — it never declares one
    /// thing and does another — so its prior needs no correction. The user is the
    /// only actor in the league who can say he is a value hunter and then behave
    /// like a spender. Generalising to 32 rows is a change of key, not of model,
    /// if AI clubs ever acquire a taste they can betray.
    ///
    /// It deliberately does NOT reset at the league-year rollover: a reputation
    /// that evaporates every February is not a reputation.
    enum TradeReputationRegistry {

        private static let defaultsKey = "tradeReputation"
        private static var scopedKey: String { CareerScopedDefaults.scopedKey(defaultsKey) }

        /// Weight one new deal carries against the accumulated read.
        ///
        /// Trades against: how fast the league changes its mind. At 0.35 three
        /// consecutive overpays move the read most of the way and one does not,
        /// which is roughly how long it takes a front office to acquire a
        /// nickname. Rejected: a plain mean, which makes the twentieth deal of a
        /// career unable to change anything.
        static let leanLearningRate = 0.35

        /// A club with no record reads as exactly average.
        static let neutralLean = 1.0

        /// Records one executed deal from `teamID`'s point of view.
        static func recordDeal(teamID: UUID, pointsSent: Int, pointsReceived: Int) {
            guard pointsSent > 0, pointsReceived > 0 else { return }
            // Clamped before it is blended: one lopsided salary dump must not be
            // able to define a front office for the rest of the career.
            let ratio = min(2.0, max(0.5, Double(pointsReceived) / Double(pointsSent)))
            var row = load(teamID: teamID)
            row.samples += 1
            row.lean = row.samples == 1
                ? ratio
                : row.lean + (ratio - row.lean) * leanLearningRate
            save(row, teamID: teamID)
        }

        /// Records one insulting proposal sent by `teamID`.
        static func recordLowball(teamID: UUID) {
            var row = load(teamID: teamID)
            row.lowballs += 1
            save(row, teamID: teamID)
        }

        /// How the rest of the league prices doing business with this club:
        /// 0.88 (nobody wants to deal with you) … 1.12 (a pleasure to do business
        /// with), and exactly 1.0 for a club nobody has a read on.
        ///
        /// Applied DIRECTIONALLY, never as one multiplier on "the price": a club
        /// in poor standing is marked down when the league prices what it is
        /// selling and marked up when the league prices what it is buying. That
        /// is what a bad reputation does, and folding it into a single ask
        /// multiplier would have made a lowballer's own players *cheaper* for him
        /// to keep and *dearer* for others to buy, which is backwards.
        ///
        /// The lean term is an inverted U on purpose. `|lean − 1|` is what
        /// costs, so the sharp operator and the soft touch are both penalised —
        /// the first because clubs stop wanting the call, the second because
        /// they price him as a mark. Only a GM who trades near chart value keeps
        /// full standing, which is the same shape the real market has.
        static func standing(teamID: UUID) -> Double {
            let row = load(teamID: teamID)
            guard row.samples > 0 || row.lowballs > 0 else { return 1.0 }
            let leanPenalty = row.samples > 0
                ? min(0.10, abs(row.lean - neutralLean) * 0.40)
                : 0.0
            let lowballPenalty = min(lowballPenaltyCap, Double(row.lowballs) * lowballPenaltyStep)
            return max(standingFloor, min(1.12, 1.0 - leanPenalty - lowballPenalty))
        }

        /// Standing lost per insulting proposal, and the ceiling on that loss.
        ///
        /// D1: these were `0.035` and a `0.14` cap under a `0.88` floor, which
        /// meant the scale **saturated at four lowballs**. A user could work
        /// through all 31 clubs and the thirty-first call was priced exactly like
        /// the fifth — the specific failure the ruling names when it says the
        /// thirty-first call in a tour must be measurably worse than the first.
        /// At 0.02 a step under a 0.22 cap it takes **eleven** lowballs to
        /// saturate, which is a TOUR rather than a bad afternoon: two or three
        /// misjudged offers cost 4-6 % and are forgivable, eleven cost the full
        /// 22 % and are a reputation.
        ///
        /// Rejected: no cap at all. An uncapped scale turns one bad week into a
        /// career-ending death spiral, and `ageOneLeagueYear` below is the
        /// counterweight that makes a bounded penalty the right shape — it hurts
        /// now, and it fades if the behaviour does.
        static let lowballPenaltyStep = 0.02
        static let lowballPenaltyCap = 0.22
        /// Worst standing any front office can reach. 0.78 is a ×1.28 surcharge
        /// on every price the league quotes him.
        static let standingFloor = 0.78

        /// Fades the lowball ledger at the league-year rollover.
        ///
        /// A reputation that never decays is not a reputation, it is a criminal
        /// record — and with the widened scale above, a single tour would
        /// otherwise price a front office at the floor for the rest of the
        /// career. At ×0.55 a saturating tour still costs most of a season, is
        /// half-forgotten a year later and is gone in three, which is roughly how
        /// long a real front office's "he wastes your time" label lasts.
        ///
        /// The `lean` half is deliberately NOT aged. That one is a read on how a
        /// man trades rather than on how he behaves, it already self-corrects
        /// through `leanLearningRate` every time he does a deal, and the type's
        /// own doc commits to it surviving February.
        static let lowballDecayPerLeagueYear = 0.55

        /// Called once at the league-year rollover, beside
        /// `TradeTalkRegistry.reset()`. Rounds DOWN so the ledger actually
        /// reaches zero (11 → 6 → 3 → 1 → 0); rounding to nearest would leave a
        /// permanent single strike on the record forever.
        static func ageOneLeagueYear() {
            guard let table = UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: [String: Double]] else { return }
            var aged = table
            for (id, var row) in table {
                row["lowballs"] = ((row["lowballs"] ?? 0) * lowballDecayPerLeagueYear).rounded(.down)
                aged[id] = row
            }
            UserDefaults.standard.set(aged, forKey: scopedKey)
        }

        /// Multiplier on how often the phone rings for this front office,
        /// 0.75 … 1.20.
        ///
        /// The other half of the inverted U, pointing the opposite way: a club
        /// the league has learned OVERPAYS gets called MORE (everyone wants that
        /// business) and a club that has been fleecing people or sending insults
        /// gets called less. Bounded so that no reputation can push §5's 3-8
        /// in-season offer band out of reach on its own, and the pity floors in
        /// `userOfferHazard` sit underneath it untouched.
        static func contactAppetite(teamID: UUID) -> Double {
            let row = load(teamID: teamID)
            guard row.samples > 0 || row.lowballs > 0 else { return 1.0 }
            // Below 1.0 means he overpays — clubs like calling him.
            let generosity = row.samples > 0 ? (neutralLean - row.lean) : 0.0
            let appetite = 1.0
                + min(0.20, max(-0.15, generosity * 0.60))
                - min(0.20, Double(row.lowballs) * 0.045)
            return max(0.75, min(1.20, appetite))
        }

        /// A one-line, honest description of the league's read, for the Trade
        /// Center. Refusal has to be VISIBLY priced (D1) or it is just a number
        /// the player never learns about.
        static func summary(teamID: UUID) -> String? {
            let row = load(teamID: teamID)
            guard row.samples > 0 || row.lowballs > 0 else { return nil }
            var parts: [String] = []
            if row.samples > 0 {
                if row.lean >= 1.10 {
                    parts.append("they think you win your trades")
                } else if row.lean <= 0.92 {
                    parts.append("they think you pay up")
                } else {
                    parts.append("you deal near chart value")
                }
            }
            if row.lowballs >= 2 {
                parts.append("\(row.lowballs) lowballs on the record")
            }
            let surcharge = Int((((1.0 / standing(teamID: teamID)) - 1.0) * 100.0).rounded())
            if surcharge >= 2 {
                parts.append("clubs are asking you ~\(surcharge) % more")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        static func reset() {
            UserDefaults.standard.removeObject(forKey: scopedKey)
        }

        // MARK: Storage

        private struct Row {
            var samples: Int = 0
            var lean: Double = TradeReputationRegistry.neutralLean
            var lowballs: Int = 0
        }

        private static func load(teamID: UUID) -> Row {
            guard let table = UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: [String: Double]],
                  let raw = table[teamID.uuidString] else { return Row() }
            return Row(
                samples: Int(raw["n"] ?? 0),
                lean: raw["lean"] ?? neutralLean,
                lowballs: Int(raw["lowballs"] ?? 0)
            )
        }

        private static func save(_ row: Row, teamID: UUID) {
            var table = UserDefaults.standard.dictionary(forKey: scopedKey) as? [String: [String: Double]] ?? [:]
            table[teamID.uuidString] = [
                "n": Double(row.samples),
                "lean": row.lean,
                "lowballs": Double(row.lowballs)
            ]
            UserDefaults.standard.set(table, forKey: scopedKey)
        }
    }

    /// How hard the rest of the league works the phones on one front office,
    /// 0.70 … 1.25, combining what it DECLARED (`FranchiseIdentity`) with what
    /// it has since been seen to DO (`TradeReputationRegistry`).
    ///
    /// This is D1's replacement for the rejected per-week trade cap, on the
    /// volume side: nothing stops the user closing a deal with all 31 clubs in a
    /// week, but a front office the league has learned to distrust finds fewer
    /// of them willing to pick up. 1.0 — today's behaviour exactly — until an
    /// identity is declared or a reputation is earned.
    static func marketAppetite(for teamID: UUID) -> Double {
        let declared = FranchiseIdentityRegistry.identity(for: teamID)?.contactAppetite ?? 1.0
        let earned = TradeReputationRegistry.contactAppetite(teamID: teamID)
        return max(0.70, min(1.25, declared * earned))
    }

    // MARK: - Negotiation Surface (Wave 3 — read-only persona exposure)

    /// Everything the Wave 3 negotiation screen is allowed to know about the GM
    /// on the other end of the phone.
    ///
    /// READ-ONLY BY DESIGN. This is a projection of numbers the market layer
    /// already computes (`GMPersona`, `TradeTalkRegistry`), never a second place
    /// they are decided — nothing here feeds a valuation, and adding a field
    /// must never change what a deal is worth. The HIDDEN parts stay hidden: no
    /// chart lean, no asking noise, no accept bar (decision §7.1 — the user's
    /// screens keep quoting plain Jimmy Johnson points). What ships is what a
    /// beat reporter would know: the man's name, how he is described around the
    /// league, roughly how far above value he opens, and how much patience he
    /// has left for this front office.
    struct GMIdentity {
        let teamID: UUID
        /// Stable GM name (`GMPersona.name`).
        let name: String
        let archetype: GMArchetype
        var archetypeLabel: String { archetype.label }
        /// One-liner for the negotiation header.
        var blurb: String { archetype.blurb }
        var symbolName: String { archetype.symbolName }
        /// Rounds of talking he tolerates before the phone stops being answered
        /// for the rest of the league year (`GMPersona.maxRounds`).
        let patience: Int
        /// Strikes his front office has already logged against the user this
        /// league year (`TradeTalkRegistry`).
        let strikes: Int
        /// How far above the value he sends this GM OPENS, in whole percent.
        /// The opening premium is public posture; the accept bar it halves into
        /// stays hidden.
        let askingPremiumPercent: Int

        /// How well the user's front office knows this man, 0 … 1
        /// (`ScoutingDossier.confidence`).
        ///
        /// D7-A's user-facing half, and the reason the fog is not a private
        /// advantage handed to the AI: the user can SEE how well he reads a GM,
        /// the same way that GM's own dossier tells him how well he reads the
        /// user. It is what his organisation has learned by doing business, and
        /// it is the same number that decides how badly the club on the other
        /// end can misprice him.
        let dossierConfidence: Double

        /// How many times the two front offices have actually done business.
        let dossierContacts: Int

        /// One line describing what the league has decided about the USER's
        /// front office, or `nil` before it has decided anything
        /// (`TradeReputationRegistry.summary`).
        let leagueRead: String?

        /// What this GM's own rejection memory is charging, in whole percent —
        /// `5 × strikes`, the `userAcceptBar` term.
        ///
        /// D1's other half is that refusal has to be VISIBLE. The strike pips
        /// already told the user how many rounds he had left; they never told
        /// him what the last one cost, which made the price the one part of the
        /// mechanic he could not learn. These two are that number, split the way
        /// the bar splits it — this man's patience, and the league's read — so a
        /// screen can quote either without recomputing anything.
        let strikeSurchargePercent: Int

        /// What the rest of the league's read on the user is charging on top,
        /// in whole percent (`1 / standing − 1`). `0` until he has done
        /// something the league noticed.
        let leagueSurchargePercent: Int

        /// Everything the two together add to this GM's price.
        var totalSurchargePercent: Int {
            Int(((1.0 + Double(strikeSurchargePercent) / 100.0)
                 * (1.0 + Double(leagueSurchargePercent) / 100.0) - 1.0) * 100.0)
        }

        /// True while he still answers the user's calls.
        var talksOpen: Bool { strikes < patience }
        /// Lowballs left before the freeze-out.
        var roundsLeft: Int { max(0, patience - strikes) }

        /// Plain-language read on how well this GM is known, for the header.
        var dossierLabel: String {
            switch dossierConfidence {
            case ..<0.01: return "Never done business"
            case ..<0.30: return "Barely know him"
            case ..<0.55: return "Getting a read"
            case ..<0.75: return "Know how he prices"
            default:      return "Know exactly what he wants"
            }
        }
    }

    /// The negotiation-facing view of one franchise's GM.
    ///
    /// `userTeamID` is optional only so existing preview/utility callers that do
    /// not have it keep compiling; supplying it is what fills in the D7-A
    /// dossier line and the league's read on the user.
    static func gmIdentity(team: Team, season: Int, userTeamID: UUID? = nil) -> GMIdentity {
        let persona = GMPersona.forTeam(
            id: team.id,
            declaredIdentity: FranchiseIdentityRegistry.identity(for: team.id)
        )
        let subject = ScoutingDossier.generalManager(
            ScoutingDossier.personID(forTeam: team.id)
        )
        return GMIdentity(
            teamID: team.id,
            name: persona.name,
            archetype: persona.archetype,
            patience: persona.maxRounds,
            strikes: TradeTalkRegistry.strikes(season: season, teamID: team.id),
            askingPremiumPercent: Int(((persona.askingPremium - 1.0) * 100.0).rounded()),
            dossierConfidence: userTeamID.map {
                ScoutingDossier.confidence(observer: $0, subject: subject)
            } ?? 0,
            dossierContacts: userTeamID.map {
                ScoutingDossier.contacts(observer: $0, subject: subject)
            } ?? 0,
            leagueRead: userTeamID.flatMap { TradeReputationRegistry.summary(teamID: $0) },
            strikeSurchargePercent: 5 * TradeTalkRegistry.strikes(season: season, teamID: team.id),
            leagueSurchargePercent: userTeamID.map {
                Int((((1.0 / max(0.5, TradeReputationRegistry.standing(teamID: $0))) - 1.0) * 100.0).rounded())
            } ?? 0
        )
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

    // MARK: - OVR anchors (#30)
    //
    // Every raw OVR number this engine compares against was picked when the
    // league averaged **76.46 OVR with sd 8.23**. The P1 calibration wave moved
    // the shipped league to **71.00 / 8.86** (`TODO.md`, "Mitattu jakauma"), so
    // an untouched 82 stopped meaning "top of the contending core" and started
    // meaning "the best player on most rosters" — the GMs quietly declared half
    // the league untouchable and the phone stopped ringing.
    //
    // The anchors below are re-derived PERCENTILE-PRESERVING rather than
    // re-guessed, the same method the wave used on `ContractEngine`'s money curve
    // and the `CALIB_*` bands:
    //
    //     new = 71.00 + (old − 76.46) × (8.86 / 8.23)
    //
    //     58 → 51 · 60 → 53 · 62 → 55 · 72 → 66 · 76 → 70.5
    //     78 → 73 · 80 → 75 · 82 → 77 · 84 → 79 · 86 → 81
    //
    // Every site that compares a raw OVR carries a `#30` marker back to this
    // note. `positionMultiplier`, the age curve and the `32 × 1.128^(OVR − 60)`
    // value curve are deliberately NOT touched: the value curve is anchored to
    // the Jimmy Johnson PICK chart, not to the league's mean, and re-pivoting it
    // would silently reprice every player against every draft pick.

    /// OVR a club assumes for an empty starter slot (street free agent).
    /// #30: 58 → 51, percentile-preserving.
    static let replacementOVR = 51.0
    /// OVR of a starter a club stops worrying about.
    /// #30: 76 → 70.5, percentile-preserving.
    static let solidStarterOVR = 70.5

    /// Grades every position on a roster by the quality of who would start.
    ///
    /// **Availability, not membership.** The model used to count everyone on the
    /// roster who was not retired, which meant a club whose starting quarterback
    /// tore a knee in week 8 read as SET at quarterback and therefore never
    /// traded for one — the single most characteristic deadline move in the
    /// sport, structurally unavailable. Two other things in the codebase answer
    /// the same question about the same roster and both filter:
    /// `PracticeSquadEngine.shorthandedPositions` and, since injured men stopped
    /// dressing, the depth chart the simulator actually reads. Three models of
    /// "we are short here" cannot disagree.
    ///
    /// Holdouts are excluded for the same reason: a man refusing to report is
    /// not covering a starter slot on Sunday, whatever the roster says.
    static func needProfile(roster: [Player]) -> NeedProfile {
        var byPosition: [Position: [Player]] = [:]
        for player in roster where !player.isRetired && !player.isInjured && !player.isHoldingOut {
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

            // A 70.5 OVR starter room is fine, 53 is a crisis; the position
            // premium (QB 1.3 … K/P 0.5) decides how loudly the hole is felt.
            // #30: the span is the distance between those two anchors and moves
            // with them — 76→60 was 16 points in the old league, 70.5→53.3 is
            // 17 in the calibrated one.
            let gap = max(0, solidStarterOVR - average)
            let weighted = gap / 17.0 * positionMultiplier(position)
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

        /// Whose proposal this view is about to price, when there is one
        /// (`respond` and `partnerVerdict` both set it from
        /// `proposal.offeringTeamID`). `nil` for the market passes that only
        /// need this club's own chair, and inert there.
        var proposerTeamID: UUID?

        /// What the LEAGUE'S read on the proposer adds to this GM's price —
        /// `1.0` for a front office nobody has a read on, up to ≈`1.28` at the
        /// standing floor.
        ///
        /// D1: this is the half that was missing, and it is the whole of "make
        /// refusal bite". `TradeReputationRegistry` already existed and already
        /// marked a lowballer down in the offers the AI BUILT for him
        /// (`buildBuyOffer`, `buildSellOffer`) and in how often the phone rang
        /// at all (`marketAppetite` → `callDepth`). What it did not touch was
        /// the bar a proposal HE builds has to clear — so a user could exhaust
        /// one GM's patience, dial the next club, and be quoted the opening
        /// price as though nothing had happened. Thirty-one times.
        ///
        /// It divides rather than multiplies for the reason the registry's own
        /// doc gives: standing is applied DIRECTIONALLY, marked down when the
        /// league prices what he sells and up when it prices what he buys, and
        /// a proposal he is pushing across the desk is the second one.
        var reputationSurcharge: Double {
            guard let proposerTeamID else { return 1.0 }
            return 1.0 / max(0.5, TradeReputationRegistry.standing(teamID: proposerTeamID))
        }

        /// The bar a user proposal must clear.
        ///
        /// Rejection memory bites twice, and the two are deliberately different
        /// shapes. `strikes` is the RELATIONSHIP — every lowball makes THIS GM
        /// 5 % more expensive for the rest of the league year and his patience
        /// ends the conversation (plan §6 Wave 2.4). `reputationSurcharge` is
        /// the LEAGUE — what the other thirty clubs have heard, which is what
        /// makes the thirty-first call in a tour worse than the first. At the
        /// extremes they compose to a bar ≈47 % above the opening one, which is
        /// a price, not a lockout: the deal is still there to be done, it simply
        /// costs what a wasted afternoon costs.
        var userAcceptBar: Double {
            persona.acceptRatio * noise * (1.0 + 0.05 * Double(strikes)) * reputationSurcharge
        }

        /// The bar another AI club has to clear — same noise, no memory (the
        /// registry only tracks how the user behaves).
        var leagueAcceptBar: Double { persona.leagueAcceptRatio * noise }

        /// True while this GM still answers the user's calls.
        var talksOpen: Bool { strikes < persona.maxRounds }


        // MARK: D7-A — what this GM looks like from another chair

        /// This club's pricing chair as ANOTHER club reads it.
        ///
        /// # What is fogged, and why exactly this
        ///
        /// The fog covers what is hidden from the league and **nothing that is
        /// on the standings page**. A club's stance is public — everyone can see
        /// a 2-7 record and a 31-year-old core — and so are its needs, because
        /// a depth chart is a depth chart. What no rival can see is the two
        /// numbers this file has always documented as HIDDEN: the GM's chart
        /// lean (`pickLean`) and how far above value he opens
        /// (`askingPremium`). Those are the read, and they are what a
        /// negotiation is actually about.
        ///
        /// # Which way the error runs
        ///
        /// The observer builds a package against his READ of the subject and
        /// the subject then decides with his TRUE numbers. So:
        ///
        /// * over-estimate the man's price and the package closes anyway — the
        ///   observer has overpaid, visibly, and the ledger records it;
        /// * under-estimate it and the deal dies at his bar, which is what a
        ///   lowball born of a bad read looks like from the outside.
        ///
        /// Both directions are therefore live, which is the ruling's
        /// requirement, and the asymmetry in their CONSEQUENCE is correct: an
        /// offer that is too small simply does not get done.
        ///
        /// # Why this cannot break preview ≡ outcome (G7)
        ///
        /// The fog is applied in exactly one place — package CONSTRUCTION — and
        /// never in `respond`, `partnerVerdict` or `hardBlocker`. A GM prices
        /// his own chair truthfully at every decision point, so the Trade
        /// Center's verdict and the executed outcome still come from the same
        /// arithmetic. Nothing the user reads is fogged; what is fogged is what
        /// the other club thought before it dialled.
        func asReadBy(_ observer: GMMarketView) -> GMMarketView {
            // A club does not need a dossier on itself.
            guard observer.team.id != team.id else { return self }

            let subject = ScoutingDossier.generalManager(
                ScoutingDossier.personID(forTeam: team.id)
            )
            let confidence = ScoutingDossier.confidence(
                observer: observer.team.id, subject: subject
            )
            let sigma = Self.valuationFogSigma * (1.0 - confidence)

            // Deterministic, mean-zero, and stable for as long as the calendar
            // slot is — same reasoning as `askNoise`, and for the same reason: a
            // read that re-rolled on every redraw would make the same club worth
            // two different things inside one advance.
            let leanDraw = readDraw(observer: observer.team.id, subject: team.id, salt: 0x11)
            let premiumDraw = readDraw(observer: observer.team.id, subject: team.id, salt: 0x22)

            var read = persona
            read.pickLean = max(0.75, min(1.30, persona.pickLean * (1.0 + leanDraw * sigma)))
            // The premium's EXCESS is what moves, not the premium: 1.16 opening
            // above value is a 16 % excess, and a 20 % error on the read is 3
            // points of ask, which is the right order of magnitude for "I think
            // he wants a bit more than he does".
            let excess = persona.askingPremium - 1.0
            let readExcess = excess * (1.0 + premiumDraw * sigma * Self.premiumFogSensitivity)
            read.askingPremium = max(1.0, min(1.32, 1.0 + readExcess))

            return GMMarketView(
                team: team,
                persona: read,
                stance: stance,
                needs: needs,
                roster: roster,
                season: season,
                week: week,
                // Carried through: a fogged read of a man is still a read of the
                // same negotiation, so the bar it implies must carry the same
                // reputation surcharge the true chair would.
                proposerTeamID: proposerTeamID
            )
        }

        /// Spread of the read on a GM nobody has met, as a share of the number
        /// being read.
        ///
        /// Trades against: how much of a negotiation is a read on a person,
        /// versus how many deals the fog kills outright. The archetype spread on
        /// `pickLean` is 0.87…1.14, so ±7 % at zero contact is about half the
        /// whole between-GM spread — enough that a stranger is genuinely hard to
        /// price, not so much that the observer's guess is unrelated to the man.
        /// Rejected: 0.15, which put the read outside the archetype spread
        /// entirely and made the whole model indistinguishable from D3's
        /// explicitly-rejected "uniform noise, turned up".
        static let valuationFogSigma = 0.07

        /// How much harder the fog bites on the opening premium than on the
        /// chart lean. Trades against: the two channels' relative loudness. The
        /// premium excess is a small number (0.05…0.25) and the lean multiplies
        /// every pick in a package, so an equal share would have made the
        /// premium channel invisible; 3× makes a strange GM's opening ask feel
        /// genuinely unpredictable while the lean stays the dominant term.
        static let premiumFogSensitivity = 3.0

        /// Deterministic mean-zero draw in −1…1 for one (observer, subject,
        /// calendar slot, channel).
        private func readDraw(observer: UUID, subject: UUID, salt: UInt64) -> Double {
            var x = TradeValueEngine.uuidDice(observer, byteOffset: 5)
            x ^= TradeValueEngine.uuidDice(subject, byteOffset: 12) &* 0x9E37_79B9_7F4A_7C15
            x ^= UInt64(bitPattern: Int64(season)) &* 0xBF58_476D_1CE4_E5B9
            x ^= UInt64(bitPattern: Int64(week + 1)) &* 0x94D0_49BB_1331_11EB
            x ^= salt &* 0xD6E8_FEB8_6659_FD93
            x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
            x = x ^ (x >> 31)
            return Double(x % 2001) / 1000.0 - 1.0
        }

        /// The directional reputation multiplier the league applies to THIS
        /// club's side of a deal (`TradeReputationRegistry.standing`).
        ///
        /// Poor standing marks down what he is selling and marks up what he is
        /// buying, which is what a bad reputation costs. 1.0 for every club the
        /// league has no read on, which is every AI club and any user who has
        /// not traded yet — so this term is inert until behaviour creates it.
        var standing: Double { TradeReputationRegistry.standing(teamID: team.id) }

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
        /// #30: every threshold here is the percentile-preserving re-derivation of
        /// the old 76.4-mean anchors (78→73, 82→77, 86→81, 84→79). Left alone
        /// they made roughly a third of the league untouchable in the calibrated
        /// league instead of the intended handful.
        func untouchableReason(_ player: Player) -> String? {
            if player.position == .QB, isStarter(player), player.overall >= 73, stance != .rebuild {
                return "\(abbreviation) aren't taking calls on their starting quarterback."
            }
            switch stance {
            case .contend:
                if player.overall >= 77 && player.age <= 27 {
                    return "\(abbreviation) hang up — \(player.lastName) is the core of a team that believes it can win now."
                }
            case .retool:
                if player.overall >= 81 && player.age <= 26 {
                    return "\(abbreviation) aren't listening on \(player.lastName). He's the one player they're building around."
                }
            case .rebuild:
                if player.overall >= 79 && player.age <= 24 {
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
    ///
    /// `proposerTeamID` is who this view is about to price a proposal FROM. It
    /// is what lets `userAcceptBar` carry the league's read on that front office
    /// (D1), and it is `nil` for every caller that only needs this club's own
    /// chair — the market passes, the offer builders, the diagnostics.
    static func marketView(
        team: Team,
        allPlayers: [Player],
        season: Int,
        week: Int,
        coreReference: Double? = nil,
        proposerTeamID: UUID? = nil
    ) -> GMMarketView {
        let roster = allPlayers.filter { $0.teamID == team.id && !$0.isRetired }
        return GMMarketView(
            team: team,
            // F-56: a club that DECLARED an identity is priced against the
            // declaration; every other club keeps the UUID draw. This is the one
            // place the declaration enters the market, so nothing downstream has
            // to know the difference between a chosen persona and a drawn one.
            persona: GMPersona.forTeam(
                id: team.id,
                declaredIdentity: FranchiseIdentityRegistry.identity(for: team.id)
            ),
            stance: stance(
                for: team,
                roster: roster,
                coreReference: coreReference ?? leagueCoreReference(allPlayers: allPlayers)
            ),
            needs: needProfile(roster: roster),
            roster: roster,
            season: season,
            week: week,
            proposerTeamID: proposerTeamID
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

        /// Career-scoped (F-06): two saves open in one install kept one pile of
        /// strikes before this, so a GM who had hung up on career A started career
        /// B already annoyed. `scopedKey` reads the bound career at every access,
        /// so a switch mid-launch needs no notification.
        private static func key(season: Int, teamID: UUID) -> String {
            CareerScopedDefaults.scopedKey("\(prefix).\(season).\(teamID.uuidString)")
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
        ///
        /// It is deliberately NOT called on a career switch any more (F-06): doing
        /// that on every cold launch is what let a user talk all 31 GMs into
        /// hanging up and then get a fresh league by quitting the app.
        ///
        /// The sweep is scoped to the OPEN career. A scoped key is
        /// `base.careerID`, so the prefix still leads and the career id trails;
        /// matching on the prefix alone would have one save's new league year wipe
        /// another save's strikes. Unbound (previews, pre-`bind`) falls back to
        /// clearing the unscoped keys, which is what gets written in that state.
        static func reset() {
            let all = UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(prefix) }
            let stale: [String]
            if let careerID = WeekAdvancer.activeCareerID {
                stale = all.filter { $0.hasSuffix(careerID.uuidString) }
            } else {
                stale = all.filter { $0.components(separatedBy: ".").count == 3 }
            }
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
        week: Int = 0,
        /// The counter this GM already has on the table, if any — the same
        /// argument `respond` takes, and passed for the same reason: he signs
        /// what he asked for, so the preview has to say so too (G7).
        standingCounter: TradeProposal? = nil
    ) -> PartnerVerdict {
        let view = marketView(
            team: aiTeam, allPlayers: allPlayers, season: currentSeason, week: week,
            proposerTeamID: proposal.offeringTeamID
        )
        if hardBlocker(
            proposal: proposal, view: view, allPlayers: allPlayers, contracts: contracts
        ) != nil {
            return .hangUp
        }
        if let standingCounter, sameAssets(proposal, standingCounter) {
            return .likeIt
        }
        // F-07: the same chart-neutral band `dealIsCoherent` runs on every offer
        // the AI assembles. It sits AFTER the compliance check on purpose — a GM
        // signs the package he himself demanded, and his own counter is his own
        // price by construction.
        if chartFairnessBlocker(
            proposal: proposal, allPlayers: allPlayers, allPicks: allPicks,
            currentSeason: currentSeason, betweenAIClubs: false
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
        rememberLowballs: Bool = true,
        /// Which round of THIS conversation the package belongs to, 1-based
        /// (task #36 — `TradeNegotiationThread.round` after the user's line is
        /// appended). Only the COUNTER reads it: a GM holds near his opening ask
        /// on the first call and walks down toward his accept bar as the talks
        /// go on (`concessionTarget`). Accept, insult and hard-blocker paths are
        /// round-blind on purpose — preview ≡ outcome (G7) is the verdict
        /// matching the outcome, and `partnerVerdict` has no round to pass.
        round: Int = 1,
        /// The counter this GM already has on the table in this conversation
        /// (`TradeNegotiationThread.pendingCounter`), if any.
        ///
        /// Task #150: a man signs what he asked for. Re-pricing his own standing
        /// demand is what let an UNCHANGED, fully complying package come back
        /// with a HIGHER ask — his week-to-week asking noise moves, and the
        /// package-decay ladder re-ranks the assets he himself added, so the
        /// deal he authored no longer cleared the bar he authored it against.
        standingCounter: TradeProposal? = nil,
        /// The week the CALENDAR is actually on, when that differs from the week
        /// the conversation is priced in (task #36).
        ///
        /// `week` above is the pricing mood and is deliberately frozen at
        /// `thread.openedWeek` (#150c) so an untouched package does not re-read
        /// "they like it" one week and "on the fence" the next. Deadline pressure
        /// is the opposite kind of fact — it is about today, not about the day
        /// the phone first rang — so `concessionCeiling` reads this instead.
        /// Defaults to the pricing week, which is right for every caller that
        /// prices and acts in the same week.
        pressureWeek: Int? = nil
    ) -> AIResponse {
        let view = marketView(
            team: aiTeam, allPlayers: allPlayers, season: currentSeason, week: week,
            proposerTeamID: proposal.offeringTeamID
        )

        // Hard rules first — clause vetoes, untouchables, the last body at a
        // position, and a GM who has stopped taking calls.
        if let blocker = hardBlocker(
            proposal: proposal, view: view, allPlayers: allPlayers, contracts: contracts,
            enforceTalkLock: rememberLowballs
        ) {
            return .rejected(reason: blocker)
        }

        // Compliance beats arithmetic: the package he demanded IS a deal.
        if let standingCounter, sameAssets(proposal, standingCounter) {
            return .accepted
        }

        // F-07: the chart-neutral band, the rule the AI's own offers have always
        // been held to and the user's never were. It runs BEFORE the value test
        // and before the insult test, because it is a league-office rule rather
        // than this GM's opinion — and it carries no strike, for the same
        // reason: a deal refused by the chart is not an insult to anybody.
        //
        // Note the deliberate ordering against the compliance check above. A GM
        // signs what he asked for, so his own standing counter is never measured
        // against the chart; the counter always runs HIS way, so there is no
        // exploit hiding in that exemption.
        if let unfair = chartFairnessBlocker(
            proposal: proposal, allPlayers: allPlayers, allPicks: allPicks,
            currentSeason: currentSeason, betweenAIClubs: false
        ) {
            return .rejected(reason: unfair)
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
            // #151: WHY he is hanging up decides what he says. An offer can fall
            // under the insult line from either direction — the usual lowball,
            // or a package so bloated that the decay ladder and the roster-spot
            // charge eat it (sixteen bodies for one man). Reading the raw chart
            // gap tells the two apart, and it must, because "his ask is far
            // above what is on the table" is simply false when the user just
            // pushed thirty times the value across the desk.
            let raw = proposalValues(
                proposal: proposal, allPlayers: allPlayers, allPicks: allPicks,
                currentSeason: currentSeason
            )
            let isOverpay = isSuspiciousOverpay(proposal: proposal, raw: raw)
            if rememberLowballs, !isOverpay {
                // An overpay is not a lowball. Scarring the relationship for it
                // would freeze a GM out over an offer that was too GENEROUS.
                let strikes = TradeTalkRegistry.addStrike(
                    season: currentSeason, teamID: aiTeam.id
                )
                // D1: refusal has to BITE beyond the one relationship. The
                // strike ends THIS conversation at this GM's patience limit; the
                // reputation row is the part that leaks across the league, so
                // working through all 31 clubs with lowballs makes the 31st call
                // measurably worse than the first. That is the replacement for
                // the per-week trade cap the ruling rejected — a real GM is
                // limited by counterparties who stop taking his calls, not by a
                // rule that counts his deals.
                TradeReputationRegistry.recordLowball(teamID: proposal.offeringTeamID)
                if strikes >= view.persona.maxRounds {
                    // The other 31 phones still work, and what the tour has
                    // already cost him at every one of them is the sentence he
                    // needs to read. Refusal is priced, so the price is quoted.
                    let league = Int((((1.0 / max(0.5, TradeReputationRegistry.standing(
                        teamID: proposal.offeringTeamID))) - 1.0) * 100.0).rounded())
                    let tail = league >= 2
                        ? " Word travels: the rest of the league is quoting you about \(league) % over the board."
                        : ""
                    return .rejected(reason: "\(view.persona.name) has heard enough. \(view.abbreviation) are done talking trade with you this league year.\(tail)")
                }
                if strikes > 1 {
                    return .rejected(reason: "\(view.abbreviation) hang up again — and \(view.persona.name) says the price just went up. He's asking \(5 * strikes) % over the board now.")
                }
            }
            return .rejected(reason: isOverpay
                ? overpayReason(view: view)
                : insultReason(view: view))
        }

        // Between the insult line and the accept bar → counter-offer.
        if let counter = buildCounter(
            proposal: proposal,
            view: view,
            gives: gives,
            gets: gets,
            round: round,
            pressureWeek: pressureWeek ?? week,
            allPlayers: allPlayers,
            allPicks: allPicks
        ) {
            // D7-A: a counter is CONTACT. The man has just told the proposer
            // what he actually wants, which is the single most informative thing
            // that can happen in a negotiation, so the proposer's dossier on him
            // fills in. One-directional and only for proposals a human really
            // sent (`rememberLowballs`) — engine probes ask a dozen clubs the
            // same question in one loop and must not teach anybody anything.
            if rememberLowballs {
                ScoutingDossier.recordContact(
                    observer: proposal.offeringTeamID,
                    subject: ScoutingDossier.generalManager(
                        ScoutingDossier.personID(forTeam: aiTeam.id)
                    )
                )
            }
            return .countered(counter.proposal, message: counter.message)
        }
        return .rejected(reason: "\(view.abbreviation) want more than you can offer right now.")
    }

    /// True when a package that failed the value test failed it by being TOO
    /// BIG rather than too small (#151).
    ///
    /// Two tells, either one is enough — but BOTH require the raw gap to run the
    /// proposer's way, because the whole point is telling an overpay from a
    /// lowball and four spare parts for a star is a lowball with a body count:
    /// - the raw Jimmy Johnson gap runs his way by half again, which is the
    ///   number every screen in the game quotes, or
    /// - the deal hands the AI three more bodies than it sends back while still
    ///   being worth at least as much, which is the shape (`rosterSpotPenalty`)
    ///   that pushes a genuine overpay under the insult line in the first place.
    static func isSuspiciousOverpay(
        proposal: TradeProposal,
        raw: (sendingValue: Int, receivingValue: Int)
    ) -> Bool {
        guard raw.sendingValue > raw.receivingValue else { return false }
        let bodySurplus = proposal.sendingPlayers.count - proposal.receivingPlayers.count
        if bodySurplus >= 3 { return true }
        return raw.sendingValue >= Int(Double(raw.receivingValue) * 1.5)
    }

    /// Brush-off for a package that is too GENEROUS to be believed — an
    /// overpay, not a lowball. A front office that is handed far more than it
    /// asked for does not celebrate; it wonders what it is being handed, and
    /// counts the lockers it would have to empty to take delivery.
    private static func overpayReason(view: GMMarketView) -> String {
        switch view.persona.archetype {
        case .oldSchool:
            return "\(view.abbreviation) hang up — \(view.persona.name) says that's far more than he asked for, and a pile that size is somebody else's problem, not a bargain."
        case .balanced:
            return "\(view.abbreviation) hang up — it's well past their asking price, and \(view.persona.name) has nowhere to put that many bodies."
        case .analytics:
            return "\(view.abbreviation) hang up — \(view.persona.name) says a package that far over the ask is a red flag: he'd be cutting most of it inside a week."
        case .aggressive:
            return "\(view.abbreviation) hang up — \(view.persona.name) doesn't want your roster, he wants the one piece that helps him."
        }
    }

    /// True when two proposals move exactly the same assets between exactly the
    /// same clubs. Order-blind (a counter rebuilds its arrays) and `id`-blind (a
    /// re-sent package is a new `TradeProposal` value).
    static func sameAssets(_ lhs: TradeProposal, _ rhs: TradeProposal) -> Bool {
        lhs.offeringTeamID == rhs.offeringTeamID
            && lhs.receivingTeamID == rhs.receivingTeamID
            && Set(lhs.sendingPlayers) == Set(rhs.sendingPlayers)
            && Set(lhs.receivingPlayers) == Set(rhs.receivingPlayers)
            && Set(lhs.sendingPicks) == Set(rhs.sendingPicks)
            && Set(lhs.receivingPicks) == Set(rhs.receivingPicks)
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

    /// The ratio this GM is holding out for in `round` — the plan §6 Wave 3
    /// concession curve ("open ~125 %, concede toward ~105 %").
    ///
    /// WHY (task #36): every counter used to be built against the accept bar plus
    /// two points, so the GM's FIRST counter was already his last, best offer.
    /// That made a multi-round thread pointless — round 3 asked for exactly what
    /// round 1 asked for — and it left `GMPersona.concessionRate` (four tuned
    /// archetype values) with no call site at all, the same dead-model shape as
    /// finding S4's `GMPersonality`.
    ///
    /// The curve: round 1 opens at his public posture (`askingPremium`, the
    /// number the negotiation header quotes as "opens ~16 % above value"), and
    /// every further round hands back `concessionRate` of the REMAINING gap down
    /// to the floor — a split-the-difference walk, geometric so it converges
    /// without ever crossing the bar he actually signs at. An aggressive GM
    /// (0.45) is most of the way there by round 3; an analytics GM (0.22) still
    /// wants a real premium on his fourth call.
    ///
    /// The rejection memory (`+5 %` a strike) and the hidden weekly noise ride on
    /// BOTH ends, exactly as `userAcceptBar` carries them, so a lowballer's whole
    /// curve shifts up rather than only its floor.
    ///
    /// TWO BOUNDS, both added because the bare geometric walk was farmable
    /// (measured: balanced gave back 98 % of its gap by round 10, aggressive
    /// 100 %, which is the whole premium for the price of tapping Counter):
    ///
    /// 1. **Patience is the round budget.** A round past `maxRounds` buys
    ///    nothing — `moved` clamps there, so the ask flattens at the point where
    ///    the man stops listening rather than sliding forever. This is what the
    ///    patience meter in the negotiation header has always claimed to mean.
    /// 2. **`ceiling` is the total he will ever concede**, from
    ///    `concessionCeiling` — his archetype's pressure-free cap, lifted by
    ///    leverage that actually exists in the world (the deadline, his own
    ///    hole at that position). Spamming the phone is not leverage.
    ///
    /// Both bounds sit ABOVE the floor by construction, so the walk-away number
    /// is still the walk-away number: `buildCounter`'s floor fallback is the one
    /// path that reaches it, and only when the user's cupboard cannot cover the
    /// ask he is actually making.
    private static func concessionTarget(
        view: GMMarketView, round: Int, ceiling: Double
    ) -> Double {
        let floor = view.userAcceptBar + 0.02
        let memory = 1.0 + 0.05 * Double(view.strikes)
        let opening = view.persona.askingPremium * view.noise * memory
        guard opening > floor else { return floor }

        let moved = min(max(0, round - 1), view.persona.maxRounds)
        let walked = 1.0 - pow(
            max(0.0, 1.0 - view.persona.concessionRate), Double(moved)
        )
        let share = min(walked, max(0.0, min(1.0, ceiling)))
        return opening - (opening - floor) * share
    }

    /// How far this GM can be talked down in THIS conversation, as a share of the
    /// opening-to-floor gap (task #36).
    ///
    /// Base is the archetype's `concessionCap` — what he gives to a patient
    /// negotiator with nothing on his side. Everything above that has to be paid
    /// for with something real:
    ///
    /// - **`deadlinePressure`** — a club four weeks from the deadline is
    ///   shopping; a club in deadline week is out of weeks. Worth up to +0.18.
    /// - **`needPressure`** — how badly the players HE would be receiving fit the
    ///   holes his own starter-quality need model found. A GM chasing the corner
    ///   he actually needs takes a thinner margin to get him. Worth up to +0.12.
    ///
    /// Hard-clamped at 0.90: no combination of pressure hands back the entire
    /// premium, because a GM who ends every negotiation at his walk-away number
    /// has no negotiating position at all.
    ///
    /// NOT a #150-style ratchet, even though the ceiling is package-dependent: the
    /// only way to lower it mid-conversation is to take the player he needs back
    /// OFF the table, and a GM who gets less accommodating when you withdraw the
    /// thing he wanted is behaving, not hardening. Complying with his counter adds
    /// a pick or drops one of HIS assets — neither touches `needPressure`.
    static func concessionCeiling(
        view: GMMarketView, proposal: TradeProposal, allPlayers: [Player],
        pressureWeek: Int
    ) -> Double {
        concessionCeiling(
            cap: view.persona.concessionCap,
            deadline: deadlinePressure(week: pressureWeek),
            need: needPressure(view: view, proposal: proposal, allPlayers: allPlayers)
        )
    }

    /// The arithmetic of the ceiling, with no model types in sight — the shape
    /// the measurement harness can compile against the shipped bytes instead of
    /// re-typing the weights.
    static func concessionCeiling(cap: Double, deadline: Double, need: Double) -> Double {
        min(0.90, cap + 0.18 * deadline + 0.12 * need)
    }

    /// 0 … 1 over the last four weeks of the trade window (week 6 → 0.25, the
    /// deadline week itself → 1.0). Zero everywhere else, which covers both the
    /// early season and every offseason week — `Career.currentWeek` only ever
    /// holds 1…9 during the regular season (it is set to 1 at the rollover and
    /// jumps to 19 at the playoffs), so the range test doubles as a phase test
    /// without `respond` having to be handed a `SeasonPhase` it never took.
    static func deadlinePressure(week: Int) -> Double {
        let ramp = 4
        guard week <= deadlineWeek, week > deadlineWeek - ramp else { return 0 }
        return Double(ramp - (deadlineWeek - week)) / Double(ramp)
    }

    /// 0 … 1: the worst hole on this GM's roster that the incoming players would
    /// plug. Read off the same `NeedProfile.severity` the valuation already uses,
    /// so "he wants this guy" means one thing everywhere.
    static func needPressure(
        view: GMMarketView, proposal: TradeProposal, allPlayers: [Player]
    ) -> Double {
        let incoming = Set(proposal.sendingPlayers)
        guard !incoming.isEmpty else { return 0 }
        return allPlayers
            .filter { incoming.contains($0.id) }
            .map { min(1.0, max(0.0, view.needs.severity($0.position))) }
            .max() ?? 0
    }

    /// Builds the counter this GM makes in `round`: the concession target first,
    /// and his signing floor as the fallback.
    ///
    /// The fallback is load-bearing. The round-1 ask is deliberately higher than
    /// the bar, and the user's cupboard is finite — without it, a package the GM
    /// would have countered before #36 could turn into "they want more than you
    /// can offer right now" and end the conversation on the opening call. He asks
    /// high, and if nothing on the board closes THAT gap he still makes the deal
    /// he was always willing to make.
    ///
    /// Task #36's cap means a late round can ask for EXACTLY what the last one
    /// asked for — he has conceded everything this conversation is worth to him.
    /// That is a legitimate outcome, but it must not be narrated as movement, so
    /// the ask is compared with the previous round's and `counterLead` says which
    /// of the two happened.
    private static func buildCounter(
        proposal: TradeProposal,
        view: GMMarketView,
        gives: Int,
        gets: Int,
        round: Int,
        pressureWeek: Int,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> (proposal: TradeProposal, message: String)? {
        let floor = view.userAcceptBar + 0.02
        let ceiling = concessionCeiling(
            view: view, proposal: proposal, allPlayers: allPlayers,
            pressureWeek: pressureWeek
        )
        let aim = concessionTarget(view: view, round: round, ceiling: ceiling)
        let previous = concessionTarget(
            view: view, round: max(1, round - 1), ceiling: ceiling
        )
        // A thousandth of a ratio point is rounding, not a concession.
        let softened = round > 1 && previous - aim > 0.001
        if aim > floor,
           let holding = counterOffer(
               proposal: proposal, view: view, gives: gives, gets: gets,
               target: aim, round: round, softened: softened,
               allPlayers: allPlayers, allPicks: allPicks
           ) {
            return holding
        }
        return counterOffer(
            proposal: proposal, view: view, gives: gives, gets: gets,
            target: floor, round: round, softened: round > 1,
            allPlayers: allPlayers, allPicks: allPicks
        )
    }

    /// One counter aimed at `target`:
    /// 1) ask for one more of the user's picks, else
    /// 2) pull the smallest AI asset out of the deal.
    ///
    /// TASK #150 — every candidate is re-priced as a WHOLE PACKAGE before it is
    /// offered, never as "the gap, minus this asset's sticker price".
    ///
    /// The old arithmetic was `deficit = gives × target − gets`, satisfied by the
    /// first spare pick whose standalone `pickValue` covered it. But this GM does
    /// not value a side linearly: `sideValue` sorts the assets and taxes every
    /// one after the best (`packageDecay`), and `rosterSpotPenalty` charges him
    /// for each extra body. So the pick he asked for arrived worth less than its
    /// sticker — and it pushed every asset already in the package one rung
    /// further down the ladder. The user complied to the letter, the re-priced
    /// package still missed the bar, and the GM countered AGAIN with a bigger
    /// ask: 435 points became 473 for handing him exactly what he demanded. A
    /// negotiation that hardens when you agree with it is not a negotiation.
    ///
    /// Re-ranking the candidate package answers it exactly: whatever this
    /// returns clears `target` in the same chair `respond` will judge it from, so
    /// a complying reply is an acceptance and the ask can only walk downward.
    private static func counterOffer(
        proposal: TradeProposal,
        view: GMMarketView,
        gives: Int,
        gets: Int,
        target: Double,
        round: Int,
        softened: Bool,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> (proposal: TradeProposal, message: String)? {
        guard gives > 0, Double(gets) < Double(gives) * target else { return nil }

        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        // Raw (undecayed) asset values for both sides of the table, from the AI's
        // chair. The ladder is re-applied from scratch per candidate below — a
        // package's worth is not the sum of its parts.
        let givesPlayers = proposal.receivingPlayers.compactMap { playerLookup[$0] }
        let givesPicks   = proposal.receivingPicks.compactMap   { pickLookup[$0] }
        let getsPlayers  = proposal.sendingPlayers.compactMap   { playerLookup[$0] }
        let getsPicks    = proposal.sendingPicks.compactMap     { pickLookup[$0] }

        let getsRaw = getsPlayers.map { view.incomingPlayerValue($0) }
            + getsPicks.map { view.pickValue($0) }

        /// `GMMarketView.sideValue`'s ladder, applied to raw values already in hand.
        func laddered(_ raw: [Double]) -> Double {
            raw.sorted(by: >)
                .enumerated()
                .reduce(0.0) { total, entry in
                    total + entry.element * max(0.20, 1.0 - view.persona.packageDecay * Double(entry.offset))
                }
        }
        /// What the AI nets from an incoming side, roster spots charged.
        func netGets(_ raw: [Double], incomingPlayers: Int, outgoingPlayers: Int) -> Double {
            max(0, laddered(raw) - view.rosterSpotPenalty(
                incomingPlayers: incomingPlayers, outgoingPlayers: outgoingPlayers
            ))
        }

        let outgoingCount = givesPlayers.count
        let incomingCount = getsPlayers.count
        let currentGives = laddered(
            givesPlayers.map { view.outgoingPlayerValue($0) } + givesPicks.map { view.pickValue($0) }
        )
        guard currentGives > 0 else { return nil }

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

        // Cheapest pick that carries the WHOLE re-ranked package over the target.
        if let addition = candidatePicks.first(where: { candidate in
            let raw = getsRaw + [view.pickValue(candidate)]
            return netGets(raw, incomingPlayers: incomingCount, outgoingPlayers: outgoingCount)
                >= currentGives * target
        }) {
            var counter = proposal
            counter.sendingPicks.append(addition.id)
            // #152: the year the league calls that draft, not the stored stamp.
            let label = "\(addition.displayDraftYear) round \(addition.round) pick"
            return (
                counter,
                "\(counterLead(view: view, round: round, softened: softened)) add your \(label) and \(view.persona.name) signs it."
            )
        }

        // Option 2: AI removes its smallest outgoing asset instead.
        var removables: [(id: UUID, isPlayer: Bool, value: Double, label: String)] = []
        for player in givesPlayers {
            removables.append((player.id, true, view.outgoingPlayerValue(player), player.fullName))
        }
        for pick in givesPicks {
            removables.append((
                pick.id, false,
                view.pickValue(pick),
                "their \(pick.displayDraftYear) round \(pick.round) pick"   // #152
            ))
        }

        // Both options answer the SAME bar now that both are priced the same way
        // — the old `target - 0.02` fudge existed only because the removal branch
        // was estimating `gives - value` off a ladder it never re-ran, and a
        // removal that merely reaches the accept bar would fail on re-submission
        // the moment the noise moved a thousandth.
        let viable = removables
            .filter { candidate in
                let remaining = removables
                    .filter { $0.id != candidate.id }
                    .map(\.value)
                let newGives = laddered(remaining)
                guard newGives > 0 else { return false }
                let newGets = netGets(
                    getsRaw,
                    incomingPlayers: incomingCount,
                    outgoingPlayers: candidate.isPlayer ? outgoingCount - 1 : outgoingCount
                )
                return newGets >= newGives * target
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
            return (
                counter,
                "\(counterLead(view: view, round: round, softened: softened)) \(removal.label) stays out of the deal."
            )
        }

        return nil
    }

    /// Lead-in for a counter line. Round 1 is a posture; later rounds have to
    /// READ as movement, because the softening itself is invisible — the user
    /// sees a smaller ask, not the ratio behind it.
    ///
    /// And when he has stopped moving (task #36's cap or his spent patience), the
    /// line has to say SO. "They come down:" over an identical ask is the tell
    /// that would teach a user to keep tapping Counter forever; a GM who says
    /// this is where he stops is the honest version of the same screen.
    private static func counterLead(view: GMMarketView, round: Int, softened: Bool) -> String {
        guard round > 1 else { return "\(view.abbreviation) counter:" }
        guard softened else {
            switch view.persona.archetype {
            case .oldSchool:  return "\(view.abbreviation) don't budge — \(view.persona.name) says the chart hasn't changed since your last call:"
            case .balanced:   return "\(view.abbreviation) hold where they are — this is their number:"
            case .analytics:  return "\(view.abbreviation) are done moving — \(view.persona.name) says the model says what it says:"
            case .aggressive: return "\(view.abbreviation) hold firm — \(view.persona.name) has given you everything he's going to:"
            }
        }
        switch view.persona.archetype {
        case .oldSchool:  return "\(view.abbreviation) move a little — \(view.persona.name) will meet you here:"
        case .balanced:   return "\(view.abbreviation) come down:"
        case .analytics:  return "\(view.abbreviation) shave the ask:"
        case .aggressive: return "\(view.abbreviation) want this done —"
        }
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
        /// Share of the league year still unpaid (task #44 pairing for #26):
        /// preview and execution price a midseason deal identically when the
        /// caller passes `CapManagementEngine.leagueYearRemaining(phase:week:)`.
        /// The 1.0 default keeps engine paths STRICTER than execution, never
        /// looser — an unthreaded caller cannot let an illegal deal through.
        leagueYearRemaining: Double = 1.0,
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

        // F-54: injured men are TRADEABLE, at a price. The flat veto that used
        // to live here took ~7 % of the league off the market at any moment,
        // including in the deadline week where a hurt starter is the whole
        // reason a club picks up the phone; real deals for injured players are
        // ordinary business with a failed-physical clause attached. The rule is
        // now a discount rather than a refusal — see `injuryMultiplier`, which
        // prices both sides of the deal identically — and the only thing left
        // here is the league's own paperwork: a man who cannot pass a physical
        // this week does not change hands this week.
        //
        // Deliberately NOT reinstated as a soft veto in the offer builders'
        // taste. `shoppingTarget` and `saleCandidates` decide separately whether
        // an AI club would build a call around a hurt player; this layer decides
        // only what is legal, and legality is symmetric between the user and the
        // 31 clubs (finding S5f / G7).

        // A franchise-tagged man is not a tradeable asset here (#132 review F6).
        // The tag is a forward commitment in `CommittedCapLedger`, keyed by
        // player and scoped to the SAVE, not to a club — so trading him carried
        // the charge to the buyer's projections while the seller, whose
        // `hasUsedTag` test is just "does anyone on my roster carry the flag",
        // was freed to tag a second player in the same offseason. Modelling the
        // real tag-and-trade (the buyer inherits the tag and the seller's tag is
        // still spent) means giving the ledger a team, which is a bigger change
        // than this rule is worth; the honest interim answer is that the man
        // does not move.
        if sendingPlayers.contains(where: \.isFranchiseTagged)
            || receivingPlayers.contains(where: \.isFranchiseTagged) {
            errors.append("Franchise-tagged players can't be traded.")
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

        // Positional integrity — the rule the body count never was (task #151).
        //
        // A head count cannot see the shape of what left. Sixteen men can go out
        // of a squad in one package and leave it "legal" on numbers while it no
        // longer has a centre, a kicker or a second corner; and in the emptied
        // offseason windows, where the floor is deliberately 28, a head count is
        // barely a rule at all. `lastManReason` already refuses to let a GM sell
        // his only body at a position, but it lives in `hardBlocker` and only
        // ever looked at the AI's side — so the user could strip his OWN roster
        // bare and nothing said a word. This is that rule, made symmetric, and
        // applied to the whole package rather than one player at a time.
        for (team, out, incoming) in [
            (offering, sendingPlayers, receivingPlayers),
            (receiving, receivingPlayers, sendingPlayers)
        ] {
            let outIDs = Set(out.map(\.id))
            var afterByPosition: [Position: Int] = [:]
            for player in allPlayers
            where player.teamID == team.id && !player.isRetired && !outIDs.contains(player.id) {
                afterByPosition[player.position, default: 0] += 1
            }
            for player in incoming where !player.isRetired {
                afterByPosition[player.position, default: 0] += 1
            }
            let stripped = out
                .map(\.position)
                .filter { (starterSlots[$0] ?? 0) >= 1 && (afterByPosition[$0] ?? 0) == 0 }
            for position in Set(stripped).sorted(by: { $0.rawValue < $1.rawValue }) {
                errors.append("\(team.abbreviation) would be left without a single \(position.rawValue) — that squad can't line up.")
            }
        }

        // Salary-cap check (skipped entirely in sandbox mode). Uses the same
        // dead-money split `TradeEngine.executeTrade` applies, so a deal that
        // validates here cannot push a team over the cap once executed.
        if capMode != .sandbox {
            let offeringSide = capDeltas(
                for: sendingPlayers, contracts: contracts, capMode: capMode,
                leagueYearRemaining: leagueYearRemaining
            )
            let receivingSide = capDeltas(
                for: receivingPlayers, contracts: contracts, capMode: capMode,
                leagueYearRemaining: leagueYearRemaining
            )

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
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> (oldHit: Int, deadCap: Int, assumed: Int) {
        let index = contractIndex(contracts)
        var oldHit = 0
        var deadCap = 0
        var assumed = 0
        for player in players {
            let split = CapManagementEngine.tradeCapSplit(
                player: player,
                contract: index[player.id],
                capMode: capMode,
                leagueYearRemaining: leagueYearRemaining
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
                  player.teamID == proposal.offeringTeamID,
                  !player.isInjured, !player.isFranchiseTagged else { return false }
        }
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id],
                  player.teamID == proposal.receivingTeamID,
                  !player.isFranchiseTagged else { return false }
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
            // From week 7 the market gets a second look at the user's roster —
            // this is the back-loaded shape §5 asks for. The roll count is
            // decided FIRST and the pity floor then lifts the CHANCE only.
            //
            // F-52: it used to be the other way round. `week >= 6 && offersSoFar
            // < 2` returned `(1, 100)` and short-circuited before the second
            // roll, so a quiet season got 1.00 + 1.00 = 3.00 expected attempts
            // in weeks 6-8 while a season already going well got 1.52 + 1.70 =
            // 3.89. The branch written to protect a quiet league year was the
            // branch suppressing it — 23 % FEWER expected attempts than a loud
            // one, doing the exact opposite of what its own comment claimed.
            let rolls = week >= 7 ? 2 : 1
            if week >= 6 && offersSoFar < 2 { return (rolls, 100) }
            return (rolls, min(94, 22 + 9 * max(0, week - 1)))

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
        //
        // D7-A / D1: the depth of that list is where a REPUTATION costs volume.
        // Twenty is a neutral front office; a club the league has learned to
        // distrust gets fifteen of the thirty-one willing to pick up, and one
        // everybody wants to do business with gets twenty-four. It is a soft
        // lever on purpose — the hard one is the price (`standing`), and stacking
        // two hard levers is how a reputation system turns into a punishment.
        let callDepth = max(12, min(26, Int((20.0 * marketAppetite(for: userTeam.id)).rounded())))
        let candidates = allTeams
            .filter { $0.id != userTeam.id && !excludingTeamIDs.contains($0.id) }
            .map { team -> (team: Team, roll: Double) in
                let weight = GMPersona.forTeam(id: team.id).initiateWeight
                return (team, Double.random(in: 0..<1) * weight)
            }
            .sorted { $0.roll > $1.roll }
            .prefix(callDepth)
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
        //
        // D7-A: the buyer does not KNOW the seller's premium, he has a read on
        // it, and the read narrows every time these two front offices do
        // business (`GMMarketView.asReadBy`). This is the whole mispricing
        // channel for offers aimed at the user: a club that has never traded
        // with him opens ~20 % off its own true number in either direction, and
        // one he has dealt with three times opens close to it.
        //
        // `standing` is the reputation term (D1 / F-56). It is 1.0 until the
        // league has watched this front office do something, and after that it
        // marks DOWN what a club in poor standing is selling — an offer for your
        // man is worth less when the league has decided you overpay, or that you
        // spend your afternoons sending insults.
        let buyerPicks = allPicks.filter { $0.currentTeamID == buyer.team.id && !$0.isComplete }
        // No room for the contract? Then the package opens with salary going the
        // other way, which is what makes the call possible at all.
        let needsRelief = !canAbsorbExactly(
            buyer: buyer.team, players: [target], contracts: contracts, capMode: capMode
        )

        // Two attempts, in the order the phone call actually goes: the buyer's
        // READ of this GM first, then — if the package his read produced is one
        // he would not himself sign, or one the league office's chart band would
        // refuse — the seller's own number.
        //
        // The second attempt is the same concession `attemptLeagueDeal`'s shape
        // 3 makes, and it is here for the same two reasons. It is true (the man
        // tells you what he wants; a phone call IS contact) and it is what keeps
        // the fog from costing VOLUME. Without it, roughly half of all fog draws
        // would kill an offer outright — a read that ran high makes the buyer
        // over-assemble until his own bar fails, a read that ran low makes the
        // package fall under the chart floor — and §5's 3-8 in-season offer band
        // would have been paid for by a design feature. With it, the fog decides
        // WHICH package the user is offered, never whether he is called at all,
        // and the mispricing survives where it belongs: in the occasional
        // conspicuously generous offer that the ledger then remembers.
        let sellerAsRead = seller.asReadBy(buyer)
        let attempts: [GMMarketView] = [sellerAsRead, seller]
        var chosen: (payment: (players: [Player], picks: [DraftPick]), proposal: TradeProposal)?
        // Kept so the funnel still tells "he could not assemble a package at all"
        // apart from "he assembled one nobody would sign" — the distinction is
        // the whole reason `printTradeDiagnostics` is worth reading.
        var assembledAnything = false

        for priced in attempts {
            // The ask is the SELLER's price (need premium + stance retention),
            // lifted by his asking premium and hidden noise — this is where the
            // "why did they want so much for him?" texture comes from.
            //
            // `standing` is the reputation term (D1 / F-56). It is 1.0 until the
            // league has watched this front office do something, and after that
            // it marks DOWN what a club in poor standing is selling: an offer
            // for your man is worth less once the league has decided you overpay,
            // or that you spend your afternoons sending insults.
            let ask = priced.outgoingPlayerValue(target)
                * priced.persona.askingPremium
                * priced.noise
                * seller.standing

            guard let payment = buildPayment(
                payer: buyer,
                // The package is assembled against the same chair the ask came
                // from: the buyer is guessing how generously this GM credits a
                // fourth-rounder, and guessing wrong is what an overpay is made
                // of.
                seller: priced,
                picks: buyerPicks,
                ask: ask,
                maxPicks: 3,
                allowFiller: true,
                preferFuture: seller.stance != .contend,
                contracts: contracts,
                capReliefSalary: needsRelief ? target.annualSalary : 0
            ) else { continue }
            assembledAnything = true

            let candidate = TradeProposal(
                offeringTeamID: buyer.team.id,
                receivingTeamID: seller.team.id,
                sendingPlayers: payment.players.map(\.id),
                receivingPlayers: [target.id],
                sendingPicks: payment.picks.map(\.id),
                receivingPicks: []
            )

            guard dealIsCoherent(
                proposal: candidate,
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
            ) else { continue }

            chosen = (payment, candidate)
            break
        }

        guard let (payment, proposal) = chosen else {
            if assembledAnything {
                funnel.offerBuyIncoherent += 1
            } else {
                funnel.offerBuyPay += 1
            }
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

        // No fog on this line and that is deliberate: a GM does not need a read
        // on anybody to know what his OWN man is worth to him. What the read
        // would cover — will this buyer pay it? — is not the seller's decision
        // here, because the offer goes to the user and the user decides.
        //
        // `standing` divides rather than multiplies, which is the directional
        // half of the reputation model: a club in poor standing is marked down
        // when the league prices what it SELLS (see `buildBuyOffer`) and marked
        // up when the league prices what it BUYS. Same read, opposite sign, and
        // together they are what a bad reputation costs per round trip.
        let ask = seller.outgoingPlayerValue(vet)
            * seller.persona.askingPremium
            * seller.noise
            / max(0.5, buyer.standing)

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
        // F-53: a public trade demand is the one thing that overrides the
        // buyer's shopping list, exactly as it already does on the AI SELLER's
        // side (`saleCandidates`). Before this the registry was the only one in
        // the codebase whose meaning was unavailable to the player who owned the
        // asset: the user's star could go public asking out and nothing in the
        // market changed — no extra calls, no discount, no premium.
        //
        // It raises both the NUMBER of calls (the interest gate drops from a
        // starter-quality hole to a passing interest, so far more clubs qualify)
        // and their AGGRESSIVENESS (a man who has asked out is the call that gets
        // made, ahead of whoever happened to be the most valuable body).
        func hasAskedOut(_ player: Player) -> Bool {
            TradeRequestRegistry.hasStandingRequest(player.id, season: seller.season)
        }
        let candidates = seller.roster.filter { player in
            // #30: 72 → 66, the same percentile floor in the calibrated league.
            // `isFranchiseTagged` is a hard league rule here, not a preference —
            // `validationErrors` vetoes the deal, so shopping one only produces
            // a call that cannot be closed (#132 review F6).
            // F-54: hurt men stay on the board while they are close to
            // returning. The value they are priced at already carries the
            // discount, so the buyer is not being fooled — he is doing what a
            // deadline buyer does.
            guard player.overall >= 66, !player.isHoldingOut,
                  !player.isFranchiseTagged else { return false }
            guard !player.isInjured || player.injuryWeeksRemaining <= shoppableInjuryWeeks
            else { return false }
            // Trades against: how loud a trade demand is, versus a market that
            // starts phoning about men nobody needs. 0.06 is "we could find him
            // snaps", which is the right bar for a player the league already
            // knows is available; 0.18 stays the bar for everyone else.
            let interestGate = hasAskedOut(player) ? 0.06 : 0.18
            guard buyer.needs.severity(player.position) >= interestGate else { return false }
            guard seller.lastManReason(player) == nil else { return false }
            guard !hasActiveNoTradeClause(player: player, contracts: contracts) else { return false }
            return true
        }
        // The man who asked out IS the call. No sampling, no five-deep shortlist:
        // when a star has gone public, that is the phone call a rival front
        // office makes, and making it the most valuable such man is what stops a
        // demand from being drowned out by an ordinary depth piece.
        if let requested = candidates
            .filter(hasAskedOut)
            .max(by: { playerTradeValue(player: $0) < playerTradeValue(player: $1) }) {
            return requested
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
    ///
    /// **The one thing that overrides the stance is the player himself.** A man
    /// whose agent has gone public asking out (`TradeRequestRegistry`) is
    /// available whatever the club's plan was that morning — that is what a
    /// front office does the day after a star says he wants to play somewhere
    /// else, and it is the entire mechanical meaning of a trade request. The
    /// hard gates above it still apply: an injured man, the last body at his
    /// position and a no-trade clause are all still no.
    static func saleCandidates(seller: GMMarketView, contracts: [Contract],
                               season: Int? = nil) -> [Player] {
        seller.roster
            .filter { player in
                // #30: 72 → 66, same percentile floor as `shoppingTarget`.
                // The tag is a hard veto in `validationErrors`, so it belongs
                // with the other hard gates rather than with the stance rules —
                // even a standing trade request cannot move a tagged man.
                // F-54: mirror of `shoppingTarget`'s gate — a seller shops a
                // man who will be back for the run-in, and lets the discount do
                // the rest.
                guard !player.isHoldingOut, player.overall >= 66,
                      !player.isFranchiseTagged else { return false }
                guard !player.isInjured || player.injuryWeeksRemaining <= shoppableInjuryWeeks
                else { return false }
                guard seller.lastManReason(player) == nil else { return false }
                guard !hasActiveNoTradeClause(player: player, contracts: contracts) else { return false }
                if TradeRequestRegistry.hasStandingRequest(player.id, season: season) { return true }
                guard seller.untouchableReason(player) == nil else { return false }
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
        /// #100: open the package with a PLAYER who fills a hole on the seller's
        /// roster instead of reaching for picks first. This is the needs swap —
        /// the shape the market could not previously express — and it is where
        /// the surplus that closes it comes from: the seller prices an incoming
        /// player at his need premium (+28 % at a crisis position) while the
        /// payer is only giving up a man he is not starting.
        openWithNeededPlayer: Bool = false,
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
        ///
        /// Still healthy-only after F-54, deliberately. A throw-in is a body the
        /// other club is being asked to accept sight unseen to close a gap; the
        /// headline asset of a deal can be a man with a knee, a make-weight
        /// cannot, and allowing it would let a package quietly become three
        /// discounted injuries wearing the value of one starter.
        func fillerPool() -> [Player] {
            payer.roster.filter { player in
                guard !player.isInjured, !player.isHoldingOut, !player.isFranchiseTagged else { return false }
                // #30: the 62-82 filler window → 55-77, percentile-preserving.
                guard player.overall >= 55, player.overall <= 77 else { return false }
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

        // #100: the needs swap opens with football, not paper. The man has to
        // fill a real hole on the seller's depth chart (severity ≥ 0.30 — a
        // starter slot he is currently covering below replacement level), and he
        // must not be one the PAYER is himself starting at a position he cannot
        // afford to thin out. Everything after this is the ordinary pick top-up.
        if allowFiller, openWithNeededPlayer {
            let alreadyIn = Set(chosenPlayers.map(\.id))
            let swap = fillerPool()
                .filter { !alreadyIn.contains($0.id) }
                .filter { seller.needs.severity($0.position) >= 0.30 }
                .filter { !(payer.isStarter($0) && payer.needs.severity($0.position) >= 0.30) }
                .filter { seller.incomingPlayerValue($0) <= ceiling }
                .max { seller.incomingPlayerValue($0) < seller.incomingPlayerValue($1) }
            // No such man on the roster — this shape does not exist for this
            // pair, and the builder says so rather than falling through to a
            // package indistinguishable from the plain rental.
            guard let swap else { return nil }
            chosenPlayers.append(swap)
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
        rosterBounds: (floor: Int, ceiling: Int),
        /// Task #88b: how the OFFERING club prices its own outgoing side today.
        /// 1.0 everywhere except deadline day, where a seller who has decided the
        /// man is going marks him down (see `urgency` in `attemptLeagueDeal`).
        /// It scales his own bar, not the buyer's — the seller is never made to
        /// accept less than he thinks the package is worth, his valuation of what
        /// he is shipping is simply lower at four o'clock than it was in October.
        sellerUrgency: Double = 1.0
    ) -> Bool {
        // Offering side must want its own proposal.
        let offeringGives = offering.sideValue(
            players: offeringSends.players, picks: offeringSends.picks, incoming: false
        ) * sellerUrgency
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
        guard chartFairnessBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: offering.season,
            betweenAIClubs: requireReceivingBar
        ) == nil else {
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

        // --- Composition (task #100). ---
        //
        // `executed` alone says the market CLEARS; it cannot say the league is
        // trading like a league. The first 8-year measurement had 285 AI-vs-AI
        // deals of which every single one was the same sentence — one veteran out,
        // future picks back — because `attemptLeagueDeal` could only ever build
        // that sentence. These counters are the instrument that makes the SHAPE of
        // the market assertable the way its volume already is.
        /// One or more players out, PICKS ONLY coming back (the classic rental).
        var shapePlayerForPicks = 0
        /// Players both ways, no picks at all (a needs swap).
        var shapePlayerForPlayer = 0
        /// Players out, players AND picks back.
        var shapePlayerForPackage = 0
        /// …of which the SELLER sweetened his own side with a pick.
        var shapeSellerSentPick = 0
        /// Deals where every returned pick was for a LATER league year.
        var shapeFuturePicksOnly = 0
        /// Deals with more than one player leaving the seller.
        var shapeMultiPlayerOut = 0
        /// Executed deals per in-season week; offseason windows fold into key 0.
        /// This is the #88b distribution — `last3Share` is a ratio and cannot say
        /// WHICH weeks carried the season.
        var executedByWeek: [Int: Int] = [:]

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
            + "capTight=\(capTight) executed=\(executed) "
            + "shape(p4pick=\(shapePlayerForPicks) p4p=\(shapePlayerForPlayer) "
            + "pkg=\(shapePlayerForPackage) sellerPick=\(shapeSellerSentPick) "
            + "futOnly=\(shapeFuturePicksOnly) multiOut=\(shapeMultiPlayerOut)) "
            + "byWeek=" + executedByWeek
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
        }

        /// Classifies one executed AI-vs-AI deal into the #100 shape buckets.
        mutating func recordShape(
            sellerPlayers: Int,
            sellerPicks: [DraftPick],
            buyerPlayers: Int,
            buyerPicks: [DraftPick],
            season: Int,
            week: Int,
            inSeason: Bool
        ) {
            let picks = sellerPicks + buyerPicks
            if buyerPlayers > 0 && picks.isEmpty {
                shapePlayerForPlayer += 1
            } else if buyerPlayers > 0 {
                shapePlayerForPackage += 1
            } else {
                shapePlayerForPicks += 1
            }
            if !sellerPicks.isEmpty { shapeSellerSentPick += 1 }
            if !picks.isEmpty, picks.allSatisfy({ $0.seasonYear > season }) {
                shapeFuturePicksOnly += 1
            }
            if sellerPlayers > 1 { shapeMultiPlayerOut += 1 }
            executedByWeek[inSeason ? week : 0, default: 0] += 1
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

    /// Roster FLOOR the market validates against in an EMPTIED offseason window.
    ///
    /// The mirror problem, and the one that actually bit: between the last game
    /// and free agency every expiring contract empties a locker, so AI rosters
    /// spend the early offseason well under the in-season 40-man floor — and a
    /// club under the floor cannot SELL anybody, which is the side of the market
    /// those windows exist for. There is no minimum roster rule in a real March.
    static let offseasonRosterFloor = 28

    /// Roster floor once the league year has been RESTOCKED.
    ///
    /// Task #151: the 28 above was measured on the hollow windows (the last game
    /// through free agency) and then applied to every non-regular-season phase —
    /// seven months in which it is not a rule anybody could hit honestly. By the
    /// pro days free agency has already refilled the average club toward the
    /// mid-40s (`FreeAgencyEngine`'s own target is 46 = 53 − a draft class), and
    /// from the draft on the class and the UDFA wave put everyone in the 80s. A
    /// floor that cannot bind is not a floor, which is a large part of why a
    /// package gutting a squad passed validation without a word. Once the lockers
    /// are filling again the club has to stay a playable football team — the same
    /// number the regular season asks for, and still well under the post-FA
    /// roster it is measured against, so nothing that could sell before is
    /// stopped from selling now.
    static let restockedRosterFloor = 40

    /// True for the offseason phases in which contracts have expired and rosters
    /// legitimately run thin — everything from the final whistle up to and
    /// including free agency itself, which is the window they refill in.
    static func isHollowRosterPhase(_ phase: SeasonPhase) -> Bool {
        switch phase {
        case .proBowl, .superBowl, .coachingChanges, .reviewRoster, .combine, .freeAgency:
            return true
        default:
            return false
        }
    }

    /// The bounds to validate against in this window.
    static func rosterBounds(for window: MarketWindow) -> (floor: Int, ceiling: Int) {
        switch window {
        case .week, .deadline:
            return (40, 75)
        case .offseason(let phase):
            return (
                isHollowRosterPhase(phase) ? offseasonRosterFloor : restockedRosterFloor,
                offseasonRosterCeiling
            )
        }
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
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> Bool {
        guard capMode != .sandbox else { return true }
        let side = capDeltas(
            for: players, contracts: contracts, capMode: capMode,
            leagueYearRemaining: leagueYearRemaining
        )
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
        /// Everything the seller sent BESIDES the headline man, already
        /// formatted ("RB Smith (74 OVR) and a 2027 round 4 pick"), or "" for a
        /// straight one-for-picks deal.
        ///
        /// #fleet review F9: `sweeten` closes a shortfall by adding a second
        /// player or a pick off the seller's own board, so the headline asset is
        /// routinely not the whole outgoing side. `TradeRecord` has always
        /// carried both sides; the roundup letter named the headline alone and
        /// understated every sweetened deal in the league.
        let extraOutgoing: String
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

    /// How many deals one club may complete inside a single market pass
    /// (task #88b).
    ///
    /// This is not a taste knob, it is the pass's arithmetic ceiling: `n` deals
    /// need `2n` distinct clubs out of 31, so a cap of one puts a hard lid of 15
    /// on any window — and the ONLY window that aims that high is deadline week.
    /// It is also the one day of the league year where a real front office does
    /// two things: a seller who has decided the season is over moves more than
    /// one veteran before four o'clock. Ordinary weeks and offseason windows keep
    /// the cap at one, so a single fire sale can never be the whole market.
    static func dealsPerClub(in window: MarketWindow) -> Int {
        switch window {
        case .deadline:          return 2
        case .week, .offseason:  return 1
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
        let attemptBudget = max(10, targetCount * dealsPerClub(in: window) * 8)
        // How many deals one club may do in this window (task #88b).
        //
        // One, ordinarily: a single fire sale must not be the whole week's
        // market. But the cap is also an arithmetic CEILING on the pass — `n`
        // deals need `2n` distinct clubs — and deadline week is the one window
        // that aims at double digits, so a 12-15 target was being asked of a
        // structure that had to find 24-30 willing clubs out of 31. Measured, it
        // converted 4-8 of 12-15 and the §5 5-15 band was missed on the low side
        // in two of five league years. Two deals per club on deadline day is both
        // the fix and simply what the real deadline looks like — a club that is
        // selling is usually selling more than one man.
        let perClubCap = dealsPerClub(in: window)
        var dealsByTeam: [UUID: Int] = [:]
        func isSpent(_ id: UUID) -> Bool { (dealsByTeam[id] ?? 0) >= perClubCap }

        while result.count < targetCount, attempts < attemptBudget {
            if sellers.isEmpty { sellers = sellerOrder().filter { !isSpent($0) } }
            guard !sellers.isEmpty else { break }
            let sellerID = sellers.removeFirst()
            attempts += 1
            guard !isSpent(sellerID), let seller = views[sellerID] else { continue }
            funnel.turns += 1

            let buyers = aiTeams
                .filter { $0.id != sellerID && !isSpent($0.id) }
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
            dealsByTeam[sellerID, default: 0] += 1
            dealsByTeam[deal.buyerID, default: 0] += 1

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
        let listed = saleCandidates(seller: seller, contracts: contracts, season: currentSeason)
        funnel.supply += listed.count
        let shopping = listed.prefix(6)
        guard !shopping.isEmpty else {
            funnel.noSupply += 1
            return nil
        }

        // Deadline urgency (task #88b). Four o'clock on deadline day is the one
        // moment in the league year when a seller's reservation price actually
        // MOVES: he has decided the man is going, there is no next week to shop
        // him in, and a rental is worth less to the buyer than a whole season of
        // the same player. So the seller prices his own asset ~8 % below what he
        // would hold out for in October — the ask, his walk-away floor and the
        // bar his own side has to clear all shift together, so he is never made
        // to sell below what he thinks the player is worth TODAY.
        //
        // This is what makes the flurry a property of the calendar rather than of
        // which clubs happened to be rebuilding: measured over five league years,
        // deadline-day volume swung 4-13 against §5's 5-15 band purely on the
        // year's stance mix, and the weak years were weak because nobody's price
        // ever came down.
        let isDeadline = window == .deadline
        let urgency = isDeadline ? 0.92 : 1.0

        // Who even takes the call (task #88b). Ordinarily a club has to have a
        // starter-quality HOLE at the position — the market is about starters,
        // not depth. On deadline day it is about depth too: a contender adds a
        // rotational body for January, and a 0.18 severity gate in a league whose
        // starter rooms mostly sit above `solidStarterOVR` means most positions
        // read as "set" and nobody picks up. Measured, that gate alone killed
        // 69-89 % of everything the sellers put on the market, and it was the
        // binding loss in exactly the league years the deadline came in under
        // §5's floor.
        let interestGate = isDeadline ? 0.10 : 0.18
        // …and how many of them he actually gets through before the hour is up.
        let callList = isDeadline ? 8 : 5

        for asset in shopping {
            funnel.assets += 1
            // D7-A moved the ask INSIDE the buyer loop. It used to be computed
            // once per asset because every club priced the seller identically;
            // now what a package has to cover is a property of the PAIR — of
            // what this buyer believes this GM wants — so it cannot be hoisted.

            let ranked = buyers
                .filter { $0.needs.severity(asset.position) >= interestGate }
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
            let interested = (fits + tight).prefix(callList)
            if interested.isEmpty { funnel.noBuyer += 1 }

            for buyer in interested {
                funnel.pairs += 1
                // D7-A: this buyer's read of this seller. The dossier is keyed
                // on the man and fills up through contact, so two clubs that
                // trade with each other every deadline price each other almost
                // exactly while two that have never spoken are guessing.
                let sellerAsRead = seller.asReadBy(buyer)
                let ask = sellerAsRead.outgoingPlayerValue(asset)
                    * sellerAsRead.persona.leagueAskingPremium
                    * sellerAsRead.noise
                    * urgency
                let buyerPicks = picksByTeam[buyer.team.id] ?? []
                let sellerPicks = picksByTeam[seller.team.id] ?? []
                let needsRelief = !canAbsorb(
                    buyer: buyer.team, salary: asset.annualSalary, capMode: capMode
                )

                // --- The sentences this phone call is allowed to speak (#100) ---
                //
                // Before this list existed there was exactly ONE: "your veteran,
                // my future picks". Measured over five league years that produced
                // 186 AI-vs-AI deals of which 186 returned nothing but future
                // picks — no player-for-player, no player+pick either way, no
                // 2-for-1. That was not a taste the GMs had; it was the only
                // package the builder could construct, and the buyer's value bar
                // (`funnel.recvBar`, 88-98 % of everything assembled) then meant
                // only the one stance pair whose pick leans diverge — a contender
                // buying from a rebuilder — could ever clear it.
                //
                // Each shape below is a real front-office move, tried in the order
                // a GM would try them, and the FIRST one both clubs sign is the
                // deal. `askFloor` is the same call made at the seller's walk-away
                // number instead of his opening ask (the concession a phone call
                // makes and a one-shot builder cannot).
                // Deliberately NOT priced through the read. Shape 3 is the
                // concession a phone call makes — the seller naming his real
                // walk-away number out loud — and a phone call IS contact, so
                // there is nothing left to be foggy about. Keeping the floor
                // truthful is also what protects the §5 volume bands from the
                // fog: a buyer whose read ran low fails shapes 1-2 and is caught
                // here, so the market clears at the seller's floor instead of
                // simply not clearing. A buyer whose read ran HIGH has already
                // closed at shape 2, having overpaid — which is the other half
                // of "mispriced in both directions".
                let askFloor = seller.outgoingPlayerValue(asset)
                    * seller.persona.leagueAcceptRatio
                    * 0.99
                    * urgency
                let wantsFuture = prefersFuturePicks(seller: seller)

                var shapes: [DealShape] = []

                // 1. THE NEEDS SWAP. The seller has a hole; the buyer has a body
                //    for it. Football back for football — and because the rosters
                //    net out, the buyer pays no roster-spot penalty either.
                if let payment = buildPayment(
                    payer: buyer, seller: sellerAsRead, picks: buyerPicks, ask: ask,
                    maxPicks: 2, allowFiller: true, preferFuture: wantsFuture,
                    contracts: contracts,
                    capReliefSalary: needsRelief ? asset.annualSalary : 0,
                    openWithNeededPlayer: true,
                    funnelCounted: false
                ), !payment.players.isEmpty {
                    shapes.append(DealShape(out: [asset], outPicks: [], payment: payment))
                }

                // 2. THE RENTAL, at the asking price. The classic deadline deal.
                if let payment = buildPayment(
                    payer: buyer, seller: sellerAsRead, picks: buyerPicks, ask: ask,
                    maxPicks: 3, allowFiller: true, preferFuture: wantsFuture,
                    contracts: contracts,
                    capReliefSalary: needsRelief ? asset.annualSalary : 0,
                    funnelCounted: true
                ) {
                    shapes.append(DealShape(out: [asset], outPicks: [], payment: payment))
                } else {
                    funnel.payFail += 1
                }

                // 3. THE SAME DEAL AT THE SELLER'S FLOOR. He opened at a premium;
                //    this is where he actually signs.
                if askFloor < ask * 0.99, let payment = buildPayment(
                    payer: buyer, seller: seller, picks: buyerPicks, ask: askFloor,
                    maxPicks: 3, allowFiller: true, preferFuture: wantsFuture,
                    contracts: contracts,
                    capReliefSalary: needsRelief ? asset.annualSalary : 0,
                    funnelCounted: false
                ) {
                    shapes.append(DealShape(out: [asset], outPicks: [], payment: payment))
                }

                var closed: DealShape?
                for var shape in shapes {
                    funnel.built += 1
                    // Cheap pre-screen on the buyer's own bar — the same
                    // arithmetic `dealIsCoherent` runs, but without building a
                    // proposal or re-indexing contracts. A shape the buyer will
                    // not sign gets ONE concession attempt: the seller closes the
                    // gap from his own side, which is where the player+pick and
                    // 2-for-1 packages in this league come from.
                    if buyerShortfall(buyer: buyer, shape: shape) > 0 {
                        guard let sweetened = sweeten(
                            shape: shape, seller: seller, buyer: buyer,
                            sellerPicks: sellerPicks, asset: asset,
                            shoppingList: listed
                        ) else {
                            funnel.recvBar += 1
                            continue
                        }
                        shape = sweetened
                    }
                    if dealIsCoherent(
                        proposal: shape.proposal(seller: seller, buyer: buyer),
                        offering: seller,
                        receiving: buyer,
                        offeringSends: (shape.out, shape.outPicks),
                        receivingSends: (shape.payment.players, shape.payment.picks),
                        allPlayers: allPlayers,
                        allPicks: allPicks,
                        allTeams: allTeams,
                        capMode: capMode,
                        contracts: contracts,
                        requireReceivingBar: true,
                        rosterBounds: rosterBounds(for: window),
                        sellerUrgency: urgency
                    ) {
                        closed = shape
                        break
                    }
                }
                guard let deal = closed else { continue }

                let proposal = deal.proposal(seller: seller, buyer: buyer)
                let returnText = offerAssetText(
                    players: deal.payment.players, picks: deal.payment.picks,
                    currentSeason: currentSeason
                )
                // #fleet review F9: the rest of the seller's side, through the
                // same formatter the return uses so the letter has one voice.
                let sweetenerPlayers = deal.out.filter { $0.id != asset.id }
                let extraOutgoing = (sweetenerPlayers.isEmpty && deal.outPicks.isEmpty)
                    ? ""
                    : offerAssetText(
                        players: sweetenerPlayers, picks: deal.outPicks,
                        currentSeason: currentSeason
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
                    pickDescription: returnText,
                    extraOutgoing: extraOutgoing
                )
                funnel.executed += 1
                funnel.recordShape(
                    sellerPlayers: deal.out.count,
                    sellerPicks: deal.outPicks,
                    buyerPlayers: deal.payment.players.count,
                    buyerPicks: deal.payment.picks,
                    season: currentSeason,
                    week: week,
                    inSeason: window.isInSeason
                )
                return (record, summary, buyer.team.id)
            }
        }
        return nil
    }


    /// The chart-neutral fairness band, in the plain Jimmy Johnson points every
    /// screen in the game quotes. Returns the refusal string, or `nil` when the
    /// deal is inside the band.
    ///
    /// # F-07 — this ran on every AI-built offer and no user-built one
    ///
    /// Before this was extracted, the guard lived inside `dealIsCoherent`, which
    /// governs the offers the AI ASSEMBLES and nothing the user proposes. A
    /// user-built package was judged solely against one GM's leaned,
    /// need-inflated ratio, with no reference to the public chart he was looking
    /// at while he built it. Combined with the persona × stance spread on an
    /// identical asset (measured at 1.5×, and at 1.97× if the future-pick
    /// multiplier is folded in) that was a value pump: buy a 30-year-old 85-OVR
    /// from a rebuilding analytics club, sell him to a needy old-school
    /// contender, repeat across 31 counterparties. The two audits priced the
    /// round trip at +60-80 % and at +531 chart points per flip respectively;
    /// the conservative figure is the acceptance target and the aggressive one
    /// is the failure case this guard has to make impossible.
    ///
    /// The band caps each LEG, which is what closes the loop. Buying, the user
    /// sends `P` for a player worth `V` and needs `P/V >= 0.82`, so the best he
    /// can do is pay 82 % of chart. Selling, he sends `V` for picks worth `P'`
    /// and needs `V/P' >= 0.82`, so the most he can extract is 122 %. The best
    /// available round trip is therefore **1.49× gross** — before the GM's own
    /// bar, his asking premium and the package decay have each taken their cut —
    /// where it was previously unbounded and measured at +128 % per flip.
    ///
    /// # Why the band is wider between two AI clubs
    ///
    /// Unchanged from where this code used to live, and it matters. For anything
    /// the user sees, the band is his protection: nobody gets phoned with an
    /// insult and nobody is offered a star for a snack, so it stays at
    /// 0.82-1.45 — the number the Trade Center's verdict is calibrated against.
    /// Between two AI clubs the JJ chart is a public language, not the rule both
    /// GMs are pricing in: a rebuilder discounts his own 30-year-old (retention
    /// ×0.82) AND marks up a future pick (stance ×1.08 × future ×1.15), and the
    /// product lands the canonical deadline trade at a neutral ratio near 1.5.
    /// The measured funnel: 91 % of packages that cleared BOTH GMs' value bars
    /// were then vetoed here. 0.72-1.70 admits that trade while still refusing
    /// the absurd, and both GMs' own bars plus `hardBlocker` have already spoken.
    static func chartFairnessBlocker(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int,
        /// True for AI-vs-AI business, false for anything the user proposes or
        /// is offered. Selects which of the two bands applies.
        betweenAIClubs: Bool
    ) -> String? {
        let floor = betweenAIClubs ? 0.72 : 0.82
        let ceiling = betweenAIClubs ? 1.70 : 1.45
        let neutral = proposalValues(
            proposal: proposal, allPlayers: allPlayers, allPicks: allPicks,
            currentSeason: currentSeason
        )
        guard neutral.receivingValue > 0 else {
            return "There's nothing on their side of the table the chart can price."
        }
        let ratio = Double(neutral.sendingValue) / Double(neutral.receivingValue)
        if ratio < floor {
            // He is taking far more than he is sending. The string names the
            // CHART, because the repo's standard is that the reason the user
            // reads is the reason the engine decided on — and this rule is the
            // public chart, not the GM's opinion of the deal.
            return "The league office won't rubber-stamp that one. On the draft-value chart you're taking \(neutral.receivingValue) points and sending \(neutral.sendingValue) — no front office signs a gap that size, whatever the GM said on the phone."
        }
        if ratio > ceiling {
            return "That's lopsided in their favour on the draft-value chart — \(neutral.sendingValue) points out for \(neutral.receivingValue) back. Nobody in this building will let you sign it."
        }
        return nil
    }

    // MARK: - Deal shapes (#100)

    /// One candidate package: what leaves the seller, and what comes back.
    private struct DealShape {
        var out: [Player]
        var outPicks: [DraftPick]
        var payment: (players: [Player], picks: [DraftPick])

        func proposal(seller: GMMarketView, buyer: GMMarketView) -> TradeProposal {
            TradeProposal(
                offeringTeamID: seller.team.id,
                receivingTeamID: buyer.team.id,
                sendingPlayers: out.map(\.id),
                receivingPlayers: payment.players.map(\.id),
                sendingPicks: outPicks.map(\.id),
                receivingPicks: payment.picks.map(\.id)
            )
        }
    }

    /// How far, in the BUYER's own currency, a shape falls short of his value
    /// bar. Zero or less means he signs. Identical arithmetic to the
    /// `requireReceivingBar` branch of `dealIsCoherent` — deliberately, so the
    /// pre-screen and the gate can never disagree.
    private static func buyerShortfall(buyer: GMMarketView, shape: DealShape) -> Double {
        let gives = buyer.sideValue(
            players: shape.payment.players, picks: shape.payment.picks, incoming: false
        )
        guard gives > 0 else { return .greatestFiniteMagnitude }
        var gets = buyer.sideValue(players: shape.out, picks: shape.outPicks, incoming: true)
        gets -= buyer.rosterSpotPenalty(
            incomingPlayers: shape.out.count,
            outgoingPlayers: shape.payment.players.count
        )
        return gives * buyer.leagueAcceptBar - gets
    }

    /// The concession a real phone call makes and a one-shot package builder
    /// cannot: the seller closes the buyer's gap from his OWN side rather than
    /// asking for less.
    ///
    /// Two currencies, cheapest first — a late pick off his own board ("and
    /// we'll send a seventh"), or a second, smaller player from the same
    /// shopping list (the 2-for-1). Exactly ONE asset is added: a market that
    /// keeps sweetening until the other side says yes is a market with no
    /// prices in it.
    private static func sweeten(
        shape: DealShape,
        seller: GMMarketView,
        buyer: GMMarketView,
        sellerPicks: [DraftPick],
        asset: Player,
        /// The seller's own shopping list, already built by the caller — the
        /// second player in a 2-for-1 has to be someone he was willing to move
        /// anyway, and rebuilding the list per sweetener call is the pass's most
        /// expensive avoidable work.
        shoppingList: [Player]
    ) -> DealShape? {
        // The sweetener may never be worth more than the deal it is closing —
        // a third of the headline asset is the ceiling, which keeps this a
        // sweetener and not a second trade bolted onto the first.
        let ceiling = seller.outgoingPlayerValue(asset) * 0.34

        var best: DealShape?
        var bestCost = Double.greatestFiniteMagnitude

        func consider(_ candidate: DealShape, cost: Double) {
            guard cost <= ceiling, cost < bestCost else { return }
            guard buyerShortfall(buyer: buyer, shape: candidate) <= 0 else { return }
            best = candidate
            bestCost = cost
        }

        // a) A pick off the seller's own board. Never his top one: a club does
        //    not sweeten with the asset it would rather keep.
        // Scanned cheapest-first and deep enough to REACH a pick that can
        // actually close a gap: a four-deep prefix only ever sees sevenths and
        // sixths, which close nothing, so the second player below always won and
        // "and we'll send a third" never appeared in the league at all.
        let spendable = sellerPicks
            .filter { $0.round >= 3 }
            .sorted { seller.pickValue($0) < seller.pickValue($1) }
        for pick in spendable.prefix(10) {
            var candidate = shape
            candidate.outPicks.append(pick)
            consider(candidate, cost: seller.pickValue(pick))
        }

        // b) A second, smaller player — the 2-for-1. He has to be someone the
        //    seller is already willing to move and cheaper than the headline.
        //
        //    `lastManReason` is a PER-PLAYER test against the pre-deal roster,
        //    so two men who each pass it can still be a club's only two at a
        //    position — and this shape ships both in one deal, leaving an AI
        //    roster with zero at a starting spot that `refillAIRosters` (which
        //    only fires below 53) will never patch. The sweetener therefore
        //    may not share a position with anything already outgoing unless
        //    the seller keeps at least two more there after the deal.
        let alreadyOut = Set(shape.out.map(\.id))
        let outgoingPositions = Set(shape.out.map(\.position))
        let seconds = shoppingList
            .filter { $0.id != asset.id && !alreadyOut.contains($0.id) }
            .filter { candidate in
                guard outgoingPositions.contains(candidate.position) else { return true }
                let keptAtPosition = seller.roster.filter {
                    $0.position == candidate.position
                        && !$0.isRetired
                        && !alreadyOut.contains($0.id)
                        && $0.id != candidate.id
                }.count
                return keptAtPosition >= 2
            }
            .filter { seller.outgoingPlayerValue($0) <= ceiling }
            .sorted { seller.outgoingPlayerValue($0) < seller.outgoingPlayerValue($1) }
        for player in seconds.prefix(4) {
            var candidate = shape
            candidate.out.append(player)
            consider(candidate, cost: seller.outgoingPlayerValue(player))
        }

        return best
    }

    /// Whether this seller wants NEXT April's picks rather than this one's.
    ///
    /// It used to be `stance != .contend`, i.e. two thirds of the league, and
    /// combined with the stance lean on future capital (rebuild ×1.15 against a
    /// contender's ×0.88) it made the future pick the ONLY currency in which a
    /// deal could clear — 100 % of five league years' deals returned nothing
    /// else. A rebuilder still always wants the future; a retooler is genuinely
    /// indifferent and takes the best board available about half the time, which
    /// is what puts current-year picks back in circulation without threatening
    /// the §5 "≥50 % of pick trades carry a future pick" floor (a package of two
    /// or three picks nearly always carries one either way).
    private static func prefersFuturePicks(seller: GMMarketView) -> Bool {
        switch seller.stance {
        case .rebuild: return true
        case .retool:  return Double.random(in: 0..<1) < 0.55
        case .contend: return false
        }
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
            .map { trade -> String in
                // #fleet review F9: name the WHOLE outgoing side. A sweetened
                // deal — the second player, the seller's own pick — read as a
                // straight one-for-picks swap here while the ledger row behind
                // it carried both.
                let extras = trade.extraOutgoing.isEmpty ? "" : " and \(trade.extraOutgoing)"
                return "• \(trade.buyerAbbr) acquire \(trade.playerPosition.rawValue) \(trade.playerName)\(extras) from \(trade.sellerAbbr) for \(trade.pickDescription)"
            }
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

            League Office
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
                        // #30: the 60-80 gap-filler window → 53-75.
                        !$0.isInjured && !$0.isFranchiseTagged && $0.position != .QB
                            && $0.overall >= 53 && $0.overall <= 75
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
        // #152: printed as the class year, matching every pick label in the UI.
        var parts: [String] = picks.map { "a \($0.displayDraftYear) round \($0.round) pick" }
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
