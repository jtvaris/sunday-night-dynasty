import Foundation

// MARK: - Negotiation Offer

/// A contract offer used in negotiations between GM and player agent.
struct NegotiationOffer: Identifiable, Equatable {
    let id = UUID()
    var years: Int              // 1-6
    var annualSalary: Int       // In thousands (e.g. 18_000 = $18M)
    var signingBonus: Int       // In thousands, spread across contract years for cap
    var guaranteedPercent: Int  // 0-100, percentage of total value guaranteed
    var noTradeClause: Bool     // Only elite players request this

    /// Performance clauses attached to the deal (TODO §5.5). Empty on every
    /// offer that does not use them, which is why it is defaulted: the
    /// memberwise init every existing caller uses is unchanged.
    var incentives: [ContractIncentive] = []

    /// Total **guaranteed-structure** value in thousands. Incentives are
    /// deliberately excluded: this is the number both sides bargain over, and
    /// folding money that may never be paid into it would let a GM "win" a
    /// negotiation with clauses the player cannot reach. What the agent is
    /// willing to count is `ContractEngine.creditedIncentiveValue`.
    var totalValue: Int { annualSalary * years + signingBonus }

    /// Ceiling of the deal — every clause hit, every year.
    var maxValue: Int {
        totalValue + ContractEngine.maxSeasonIncentiveValue(incentives) * max(0, years)
    }

    /// Guaranteed money in thousands.
    var guaranteedMoney: Int { Int(Double(totalValue) * Double(guaranteedPercent) / 100.0) }

    /// Annual cap hit including prorated signing bonus. Incentives are absent on
    /// purpose — they are charged when earned, at season end
    /// (`ContractEngine`'s "Cap treatment" note).
    var annualCapHit: Int {
        let proratedBonus = years > 0 ? signingBonus / years : 0
        return annualSalary + proratedBonus
    }

    /// Year-by-year breakdown of the offer for preview purposes.
    /// Uses escalating structure for display (young player default).
    func yearlyBreakdown(playerAge: Int = 25) -> [ContractYearDetail] {
        guard years > 0 else { return [] }
        let proratedPerYear = signingBonus / years

        // Build base salaries with escalating/front-loaded structure
        let baseSalaries: [Int]
        if playerAge < 28 {
            baseSalaries = ContractEngine.escalatingBaseSalaries(annualSalary: annualSalary, years: years)
        } else {
            baseSalaries = ContractEngine.frontLoadedBaseSalaries(annualSalary: annualSalary, years: years)
        }

        return (0..<years).map { yearIndex in
            let base = yearIndex < baseSalaries.count ? baseSalaries[yearIndex] : annualSalary
            let yearCapHit = base + proratedPerYear
            let remainingFromThisYear = years - yearIndex
            let deadCapIfCut = proratedPerYear * remainingFromThisYear

            return ContractYearDetail(
                yearNumber: yearIndex + 1,
                baseSalary: base,
                proratedBonus: proratedPerYear,
                capHit: yearCapHit,
                deadCapIfCut: deadCapIfCut
            )
        }
    }
}

// MARK: - Negotiation Message

/// A single message in the negotiation chat.
struct NegotiationMessage: Identifiable {
    let id = UUID()
    let sender: NegotiationSender
    let text: String
    let offer: NegotiationOffer?
    let timestamp = Date()

    enum NegotiationSender {
        case agent
        case gm
        case system  // "Deal completed", "Negotiations broke down"
    }
}

// MARK: - Negotiation State

enum NegotiationOutcome {
    case pending
    case dealReached(NegotiationOffer)
    case walkedAway
    case playerWalked
    /// R22: a hardliner agent was insulted by a lowball — talks are dead for
    /// the rest of the offseason (persisted via `NegotiationLockRegistry`).
    case negotiationsBrokenOff
}

// MARK: - Negotiation Context

enum NegotiationType {
    case extend    // Extending current player's contract
    case freeAgent // Signing a free agent
}

// MARK: - GM Standing & Negotiation Factor

/// What the league knows about the user's front office, as numbers.
///
/// Passed IN rather than fetched, so the demand model stays a pure function of
/// its arguments and can be unit-checked, previewed and run from the balance
/// harness without a `ModelContext`. `neutral` is the identity: a brand-new
/// career negotiates at exactly market.
struct GMStanding {
    /// `Career.legacy.mediaReputation`, −100 (villain) … 100 (beloved).
    var mediaReputation: Int
    /// `Career.legacy.totalPoints`.
    var legacyPoints: Int
    /// `DraftReputation.ownerTrust`, 0…100. **70 is the neutral default** the
    /// model is written around, not 50 — that is the value the row is created
    /// with, so an owner who has never reacted to anything must cost nothing.
    var ownerTrust: Int
    /// `Career.winPercentage`, 0…1.
    var winPercentage: Double
    /// `Career.championships`.
    var championships: Int
    /// `NegotiationLedger.hardballReputation()` — history, not standing, but it
    /// belongs to the same GM and enters the same sum.
    var hardballReputation: Double

    static let neutral = GMStanding(
        mediaReputation: 0, legacyPoints: 0, ownerTrust: 70,
        winPercentage: 0.5, championships: 0, hardballReputation: 0
    )

    /// Reads a live career. `ownerTrust` is a separate `DraftReputation` row,
    /// so it is a parameter: callers that have not fetched one leave the owner
    /// out of the calculation rather than guessing at it.
    static func from(career: Career, ownerTrust: Int = 70) -> GMStanding {
        GMStanding(
            mediaReputation: career.legacy.mediaReputation,
            legacyPoints: career.legacy.totalPoints,
            ownerTrust: ownerTrust,
            winPercentage: career.winPercentage,
            championships: career.championships,
            hardballReputation: NegotiationLedger.hardballReputation()
        )
    }
}

/// How much the GM himself is worth on an agent's ask, itemised.
///
/// **Why itemised.** A single opaque number would be the same feature with none
/// of the teaching in it. The player is supposed to learn that winning, a clean
/// press relationship and a reputation for dealing straight are *worth money at
/// the table* — which he can only learn if the negotiation screen can show him
/// which of the five is helping and which is costing. The chat layer renders
/// these; the engine never writes the labels.
struct GMAdjustment {

    /// The five standing inputs. Raw-value backed so the chat layer can key its
    /// copy off them without importing the engine's ordering.
    enum Source: String, CaseIterable {
        /// Press relationship (`LegacyTracker.mediaReputation`).
        case mediaRespect
        /// Career achievement — legacy points and rings.
        case legacy
        /// The owner's confidence in the football operation.
        case ownerTrust
        /// How the club has been doing lately.
        case recentWinning
        /// This save's negotiating history (`NegotiationLedger`).
        case hardballReputation
    }

    struct Component: Equatable {
        let source: Source
        /// Signed fraction. **Negative is good for the GM** — it is a discount
        /// on the ask; positive means agents charge him more.
        let value: Double
    }

    /// Always all five, in `Source.allCases` order, including zeroes — a
    /// breakdown that hides its neutral rows teaches nothing.
    let components: [Component]

    /// Sum before clamping, exposed so a UI can say "capped".
    var rawTotal: Double { components.reduce(0) { $0 + $1.value } }

    /// The fraction actually applied, clamped to ``bounds``.
    var total: Double {
        Swift.min(GMAdjustment.bounds.upperBound,
                  Swift.max(GMAdjustment.bounds.lowerBound, rawTotal))
    }

    /// The multiplier the ask is scaled by. `< 1` is a discount.
    var factor: Double { 1.0 + total }

    func value(_ source: Source) -> Double {
        components.first { $0.source == source }?.value ?? 0
    }

    /// Bounds on the whole GM term.
    ///
    /// The brief for this system is "a good GM gets 3-8 % off, a bad one pays
    /// 5-15 % more", and the asymmetry is deliberate: an agent's willingness to
    /// discount for a well-run building is bounded by his duty to his client,
    /// while his willingness to charge a badly-run one is bounded only by the
    /// market. Being good is worth less than being bad costs — which is also
    /// how it works.
    static let bounds: ClosedRange<Double> = -0.08 ... 0.15

    static let neutral = GMAdjustment(
        components: Source.allCases.map { Component(source: $0, value: 0) }
    )
}

// MARK: - Situation

/// The facts about the club and the season that the demand model reads.
///
/// Same rule as `GMStanding`: passed in, never fetched. Every field has a
/// neutral default so a caller that only knows the player still gets a sane
/// demand — `ContractNegotiationEngine.situation(for:)` fills the
/// player-derived half automatically.
struct NegotiationSituation {
    /// The league year this conversation belongs to.
    ///
    /// Load-bearing for the refusal model and nothing else: a stance verdict
    /// that is a pure function of a fixed UUID roll never changes, so a
    /// 35-year-old who draws `.ridingIntoRetirement` once would refuse every
    /// league year for the rest of his career. The season salts the roll, so the
    /// answer is stable inside a season (which is what a persisted thread needs)
    /// and re-drawn at the new league year (which is what a career needs).
    var season: Int = 0
    /// The club's record this season, as a fraction. 0.5 is neutral.
    var teamWinPercentage: Double = 0.5
    var teamWins: Int = 0
    var teamLosses: Int = 0
    /// Regular-season weeks already played — how much the record is worth as
    /// evidence, and the gate on "he hasn't started a game all year".
    var weeksPlayed: Int = 0
    /// The club is a real contender this season. A legacy-hunter discounts for
    /// this and only this.
    var isContender: Bool = false
    /// He is coming off the best season of his career and both sides know it.
    var cameOffCareerYear: Bool = false

    static let neutral = NegotiationSituation()
}

// MARK: - Contract Demand

/// **The demand model.** What one agent wants, what he will not go below, and
/// what frame he is in — computed before a single offer is made.
///
/// This is the pinned contract between the economy layer and the chat layer:
/// the engine owns every number in here, the chat layer owns every word said
/// about them. Nothing downstream of this type computes money.
///
/// It is **deterministic**. The old opening ask multiplied market value by
/// `Double.random(in: 1.08...1.18)`, so closing the sheet and reopening it
/// quoted a different price for the same man — tolerable when a negotiation
/// lived inside one modal, indefensible now that it is a persisted conversation
/// the user can walk away from and come back to. The jitter is now a UUID draw
/// on a byte no other agent trait uses, so the ask is stable for the life of
/// the save and still differs from player to player.
struct ContractDemand {

    // MARK: Identity
    let playerID: UUID
    let persona: AgentPersona
    let negotiationType: NegotiationType

    // MARK: Money (all in thousands, all PER YEAR)
    /// `ContractEngine.estimateMarketValue` — the unadjusted market.
    let marketValue: Int
    /// What the agent opens at.
    let askAmount: Int
    /// The number below which the conversation stops being a negotiation. An
    /// offer at or above it draws a professional counter; 25 % under it is an
    /// insult.
    let floorAmount: Int

    // MARK: Structure
    let askYears: Int
    /// The bonus on the opening ask. Stored rather than derived so
    /// ``openingOffer`` is deterministic: `annualCapHit` (salary + bonus/years)
    /// is what every threshold in this file is graded against, so a bonus drawn
    /// from `Double.random` would swing the number the negotiation turns on by
    /// ±2.3 % on every call that re-priced the same man.
    let askSigningBonus: Int
    let guaranteedPercent: Int
    let wantsNoTradeClause: Bool
    /// He wants a short deal to bet on himself, not because of his age.
    let isProveIt: Bool

    // MARK: Stance
    /// The frame the conversation OPENS in. Never `.insulted` — that is a
    /// verdict on an offer, and no offer has been made yet.
    let personaTone: AgentToneKey
    /// Set only when `personaTone == .refusing`.
    let refusalReason: AgentRefusalReason?

    // MARK: Breakdown
    let gmAdjustment: GMAdjustment
    let situationBreakdown: SituationBreakdown
    /// How many lowballs this conversation has already absorbed. Each one
    /// ratchets the ask and costs the agent a round of patience.
    let insultCount: Int

    var isRefusing: Bool { personaTone == .refusing }

    /// Patience left after the insults this thread has already taken.
    var maxRounds: Int { max(1, persona.maxRounds - insultCount) }

    /// The share of the current ask the agent treats as his floor.
    let floorFraction: Double

    /// The opening offer the agent puts on the table, in the shape the rest of
    /// the negotiation speaks.
    var openingOffer: NegotiationOffer {
        NegotiationOffer(
            years: askYears,
            annualSalary: askAmount,
            signingBonus: askSigningBonus,
            guaranteedPercent: guaranteedPercent,
            noTradeClause: wantsNoTradeClause
        )
    }

    // MARK: Tone

    /// Grade an offer against this demand.
    ///
    /// `currentAskPerYear` is the agent's *standing* number, which is the
    /// opening ask on round one and his latest counter after that — the floor
    /// has to travel with the ask or an agent who has already come down twice
    /// would keep judging offers against a price he abandoned.
    ///
    /// Thresholds, and why they sit where they do:
    ///
    /// | offer, per year | verdict | what happens |
    /// |---|---|---|
    /// | ≥ ask × 0.97 | `.eager` | he signs |
    /// | ≥ floor | `.professional` | he counters, close to the middle |
    /// | ≥ floor × 0.75 | `.hardline` | he counters with a number and barely moves |
    /// | < floor × 0.75 | `.insulted` | the ask goes UP and patience drops |
    ///
    /// The floor is the pivot rather than the ask because "25 % under" has to
    /// mean 25 % under something an agent would actually have taken. Measured
    /// off the ask it would punish a GM for the agent's own opening theatre.
    func tone(for offer: NegotiationOffer, currentAskPerYear: Int) -> AgentToneKey {
        tone(forPerYear: offer.annualCapHit, currentAskPerYear: currentAskPerYear)
    }

    /// The same verdict on a per-year number the caller has already adjusted —
    /// the engine credits performance clauses and discounts a thin guarantee
    /// before grading, and both of those change what the offer is *worth* per
    /// year without changing what it says.
    func tone(forPerYear offered: Int, currentAskPerYear: Int) -> AgentToneKey {
        guard !isRefusing else { return .refusing }
        let ask = max(1, currentAskPerYear)
        let floor = max(1, Int(Double(ask) * floorFraction))
        if offered >= Int(Double(ask) * ContractNegotiationEngine.acceptRatio) { return .eager }
        if offered >= floor { return .professional }
        if offered >= Int(Double(floor) * ContractNegotiationEngine.insultRatio) { return .hardline }
        return .insulted
    }

    /// The demand after a lowball: the ask ratchets, the floor rides up with it
    /// and one round of patience is gone.
    ///
    /// An agent who is insulted and then quietly comes down anyway is not a
    /// negotiator, he is a vending machine. This is the one place in the model
    /// where the price moves the WRONG way for the GM, and it is what makes a
    /// lowball a decision rather than a free probe.
    func escalated() -> ContractDemand {
        ContractDemand(
            playerID: playerID,
            persona: persona,
            negotiationType: negotiationType,
            marketValue: marketValue,
            askAmount: Int(Double(askAmount) * ContractNegotiationEngine.insultRatchet),
            floorAmount: Int(Double(floorAmount) * ContractNegotiationEngine.insultRatchet),
            askYears: askYears,
            askSigningBonus: Int(Double(askSigningBonus) * ContractNegotiationEngine.insultRatchet),
            guaranteedPercent: guaranteedPercent,
            wantsNoTradeClause: wantsNoTradeClause,
            isProveIt: isProveIt,
            personaTone: personaTone,
            refusalReason: refusalReason,
            gmAdjustment: gmAdjustment,
            situationBreakdown: situationBreakdown,
            insultCount: insultCount + 1,
            floorFraction: floorFraction
        )
    }

    // MARK: Situation breakdown

    /// Why the ask is not simply market value, itemised the same way
    /// ``GMAdjustment`` is.
    struct SituationBreakdown {
        enum Source: String, CaseIterable {
            /// Who represents him (`AgentPersona.demandFactor`).
            case agentPersona
            /// The man's temperament.
            case archetype
            /// What he plays for.
            case motivation
            /// How he feels about the building right now.
            case morale
            /// His headspace (`MotivationState`).
            case motivationState
            /// Age, form and the tag — everything that decides who needs whom.
            case leverage
            /// Whether this club is somewhere he wants to be.
            case teamSituation
            /// The GM (`GMAdjustment.total`, folded in as one line).
            case frontOffice
        }

        struct Component: Equatable {
            let source: Source
            /// Signed fraction applied multiplicatively. Positive = costs more.
            let value: Double
        }

        let components: [Component]

        /// Product of `(1 + value)`, clamped to ``bounds``.
        var multiplier: Double {
            let raw = components.reduce(1.0) { $0 * (1.0 + $1.value) }
            return Swift.min(SituationBreakdown.bounds.upperBound,
                             Swift.max(SituationBreakdown.bounds.lowerBound, raw))
        }

        func value(_ source: Source) -> Double {
            components.first { $0.source == source }?.value ?? 0
        }

        /// Nothing in this model may price a man at less than three quarters of
        /// his market or more than half again — past those the ask stops being
        /// a negotiating position and starts being a bug.
        static let bounds: ClosedRange<Double> = 0.72 ... 1.50
    }
}

// MARK: - Negotiation Engine

/// Handles the logic of contract negotiations between GM and player agent.
/// Agent evaluates offers based on market value, player age, morale, and team factors.
enum ContractNegotiationEngine {

    // MARK: - Tone Thresholds
    //
    // The four numbers the whole conversation turns on, in one place so the
    // chat layer can quote them and the balance harness can sweep them.

    /// Share of the standing ask that closes the deal. Not 1.00: an agent who
    /// holds out for the last 3 % of a number he invented has stopped
    /// representing his client.
    static let acceptRatio = 0.97

    /// Share of the FLOOR below which an offer stops being low and starts being
    /// an insult. 0.75 is the brief's "25 % under the floor".
    static let insultRatio = 0.75

    /// What a lowball costs the GM: the ask (and the floor with it) moves up
    /// 6 %, and `ContractDemand.maxRounds` loses a round.
    static let insultRatchet = 1.06

    // MARK: - Demand Model

    /// **The entry point.** Everything an agent wants, before any offer exists.
    ///
    /// Callable with nothing but a player: `situation` and `standing` both have
    /// neutral identities, so a preview or a list row can price a man without
    /// assembling the world. The chat layer passes the real ones.
    ///
    /// The refusal verdict is part of the return value precisely because the
    /// brief requires it to be knowable BEFORE the GM says anything — the
    /// conversation has to be able to open with "he won't talk to you".
    ///
    /// - Parameter insultCount: how many lowballs this conversation has already
    ///   absorbed. **The chat layer must pass its persisted count**: the demand
    ///   is a pure function, so recomputing it fresh every round resets the
    ///   count to zero, and with it `maxRounds` — which is what made the
    ///   documented "patience −1 per insult" a no-op in the shipped path.
    static func demand(
        player: Player,
        negotiationType: NegotiationType,
        salaryCap: Int = 265_000,
        situation: NegotiationSituation = .neutral,
        standing: GMStanding = .neutral,
        insultCount: Int = 0
    ) -> ContractDemand {
        let persona = AgentPersona.forPlayer(id: player.id)
        let market = ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)
        let gm = gmAdjustment(standing)
        let breakdown = situationBreakdown(
            player: player, persona: persona, negotiationType: negotiationType,
            situation: situation, gm: gm
        )

        // Deterministic opening theatre: every agent opens a little above where
        // he means to land, and how much is a property of the man, not of the
        // moment the sheet was opened.
        let theatre = 1.04 + 0.08 * unitDraw(player.id, salt: 0x51)
        let raw = Double(market) * breakdown.multiplier * theatre

        // The old ask was floored at market value — an agent could never open
        // below it. That floor is what made the loyalty and legacy-hunter
        // discounts invisible: the model computed them and then threw them
        // away, so a captain re-signing with the club he has given six years to
        // opened at exactly the same number as a mercenary. He now opens under
        // market, and the player can see that he is being offered a discount
        // rather than having to take it on faith.
        //
        // The band is absolute: never under the veteran minimum, never outside
        // 0.75-1.60× market whatever the multipliers stack up to.
        let minimum = max(Int(0.0028 * Double(salaryCap)), 750)
        let banded = Swift.min(Double(market) * 1.60, Swift.max(Double(market) * 0.75, raw))
        // Every lowball this conversation has already absorbed rides on top of
        // the band: the insult premium is charged ABOVE the market, which is the
        // whole point of it.
        let insults = max(0, insultCount)
        let ratchet = pow(insultRatchet, Double(insults))
        let ask = max(minimum, Int(banded * ratchet))

        let fraction = floorFraction(player: player, persona: persona, situation: situation)
        // A free agent taking meetings is BY DEFINITION at the table — "you
        // never play me" is not a thing to say to a club he has never played
        // for. The refusal model is therefore an extension-only gate, and living
        // here rather than at the call site is what stops one surface from
        // asking a question another surface answers differently.
        let refusal = negotiationType == .extend
            ? refusalVerdict(player: player, situation: situation, gm: gm)
            : nil
        let proveIt = wantsProveItDeal(player: player, situation: situation)

        return ContractDemand(
            playerID: player.id,
            persona: persona,
            negotiationType: negotiationType,
            marketValue: market,
            askAmount: ask,
            floorAmount: Int(Double(ask) * fraction),
            askYears: preferredYears(player: player, isProveIt: proveIt),
            askSigningBonus: ContractEngine.signingBonus(
                annualSalary: ask, draw: unitDraw(player.id, salt: 0x3F)
            ),
            guaranteedPercent: preferredGuaranteedPercent(player: player, persona: persona),
            wantsNoTradeClause: player.overall >= 90 && unitDraw(player.id, salt: 0x9C) < 0.5,
            isProveIt: proveIt,
            personaTone: refusal == nil ? openingTone(persona: persona, player: player) : .refusing,
            refusalReason: refusal,
            gmAdjustment: gm,
            situationBreakdown: breakdown,
            insultCount: insults,
            floorFraction: fraction
        )
    }

    // MARK: - Close Tone

    /// **The tone a signed deal closed in** — the number the morale write is
    /// keyed on, graded by the side that owns the numbers.
    ///
    /// The chat layer used to derive this itself, on `totalValue` against the
    /// opening ask, and the two metrics disagreed: a GM who paid the agent's own
    /// standing counter on round 3 (a deal `respond` graded `.eager`) was booked
    /// as `.hardline`, costing him 4 points of morale and a lingering grudge for
    /// accepting the agent's number verbatim. This grades the same per-year cap
    /// hit `respond` grades, against the OPENING ask, so a close can never be
    /// harsher than the money says it was.
    ///
    /// The journey still counts — that is what the round check is — but only in
    /// the direction of taking the shine off a good close, never of turning a
    /// deal the agent proposed into one he resents.
    static func closeTone(
        signedPerYear: Int,
        openingAskPerYear: Int,
        rounds: Int,
        demand: ContractDemand
    ) -> AgentToneKey {
        switch demand.tone(forPerYear: signedPerYear, currentAskPerYear: openingAskPerYear) {
        case .eager:
            // Got his opener, or within 3 % of it. A grind still dulls it.
            return rounds <= 2 ? .eager : .professional
        case .professional:
            // Landed between his floor and his opener: fine, unless it took
            // every round of patience he had.
            return rounds <= 3 ? .professional : .hardline
        case .hardline, .insulted, .refusing:
            // Signed below the floor he said he had. He remembers.
            return .hardline
        }
    }

    /// The one number the GM's standing is worth, for callers that want the
    /// multiplier without the breakdown. `< 1.0` is a discount.
    static func gmNegotiationFactor(_ standing: GMStanding) -> Double {
        gmAdjustment(standing).factor
    }

    /// The player-derived half of a situation, so a caller only has to supply
    /// what it actually knows about the club and the season.
    static func situation(
        for player: Player,
        season: Int = 0,
        teamWins: Int = 0,
        teamLosses: Int = 0,
        weeksPlayed: Int = 0,
        isContender: Bool = false
    ) -> NegotiationSituation {
        let played = max(0, teamWins + teamLosses)
        return NegotiationSituation(
            season: season,
            teamWinPercentage: played == 0 ? 0.5 : Double(teamWins) / Double(played),
            teamWins: teamWins,
            teamLosses: teamLosses,
            weeksPlayed: weeksPlayed,
            isContender: isContender,
            // A career year, from what a `Player` row actually knows: he started
            // essentially every game and the building is happy with him. It is a
            // proxy, and a deliberately conservative one — a caller holding real
            // `PlayerSeasonHistory` should overwrite it.
            cameOffCareerYear: player.gamesStartedThisSeason >= 15 && player.morale >= 70
        )
    }

    // MARK: - GM Factor

    /// Turns the user's standing into the five-line adjustment an agent applies.
    ///
    /// Every term is signed so that **negative is a discount**, and every term
    /// is individually clamped before the sum is clamped — so no single input
    /// can carry the whole factor, which is what stops the feature from
    /// collapsing into "win games, pay less".
    static func gmAdjustment(_ s: GMStanding) -> GMAdjustment {
        // Press. A beloved GM is a place agents want their clients seen; a
        // villain is a risk they price.
        let media = clamp(-Double(s.mediaReputation) / 100.0 * 0.030, 0.030)

        // Achievement. Saturating, because the tenth ring does not open a door
        // the first one left shut. 1 200 legacy points is a full career.
        let legacyRaw = Swift.min(1.0, Double(s.legacyPoints) / 1_200.0) * 0.025
            + Swift.min(3.0, Double(s.championships)) * 0.005
        let legacy = -clamp(legacyRaw, 0.040)

        // The owner. 70 is the neutral row value, not 50 — see `GMStanding`.
        let owner = clamp(Double(70 - s.ownerTrust) / 100.0 * 0.05, 0.020)

        // The record. Half a season of evidence is already in the win
        // percentage the caller passes; this only prices it.
        let winning = clamp((0.5 - s.winPercentage) * 0.08, 0.030)

        // History (`NegotiationLedger`) — already bounded at source.
        let hardball = s.hardballReputation

        return GMAdjustment(components: [
            .init(source: .mediaRespect, value: media),
            .init(source: .legacy, value: legacy),
            .init(source: .ownerTrust, value: owner),
            .init(source: .recentWinning, value: winning),
            .init(source: .hardballReputation, value: hardball),
        ])
    }

    // MARK: - Situation Breakdown

    private static func situationBreakdown(
        player: Player,
        persona: AgentPersona,
        negotiationType: NegotiationType,
        situation: NegotiationSituation,
        gm: GMAdjustment
    ) -> ContractDemand.SituationBreakdown {
        let isOwnClub = negotiationType == .extend

        // Who represents him. The persona factors are the R22 ones, expressed
        // as deltas so they read on the same scale as everything below.
        let agent = persona.demandFactor - 1.0

        // Temperament. A drama queen and a lone wolf are the mercenaries; a
        // captain and a mentor are the men who leave money on the table — and
        // only for the club they already play for, which is what `isOwnClub`
        // halves.
        let archetypeRaw: Double = {
            switch player.personality.archetype {
            case .dramaQueen:        return 0.08
            case .loneWolf:          return 0.05
            case .fieryCompetitor:   return 0.03
            case .classClown:        return 0.01
            case .feelPlayer:        return 0.0
            case .steadyPerformer:   return -0.02
            case .quietProfessional: return -0.03
            case .mentor:            return -0.05
            case .teamLeader:        return -0.06
            }
        }()
        let archetype = archetypeRaw < 0 && !isOwnClub ? archetypeRaw * 0.4 : archetypeRaw

        // What he plays for. The legacy-hunter clause lives here: a
        // winning-motivated man discounts, and discounts twice as hard for a
        // club that is actually going somewhere.
        let motivationRaw: Double = {
            switch player.personality.motivation {
            case .money:   return 0.12
            case .fame:    return 0.08
            case .stats:   return 0.03
            case .winning: return situation.isContender ? -0.12 : -0.06
            case .loyalty: return isOwnClub ? -0.10 : -0.03
            }
        }()

        // How he feels about the place. An unhappy man is expensive: money is
        // the only apology a club can make in a contract.
        let morale: Double = {
            switch player.morale {
            case ..<40:   return 0.08
            case 40..<55: return 0.04
            case 55..<70: return 0.0
            case 70..<85: return -0.02
            default:      return -0.05
            }
        }()

        // Headspace. `MotivationState.complacent` is reachable only through the
        // post-payday trigger, which makes "just got paid, wants paying again"
        // a state the model can see rather than one it has to guess at.
        let state: Double = {
            switch player.motivationState {
            case .driven:      return -0.02
            case .focused:     return 0.0
            case .complacent:  return 0.03
            case .discouraged: return 0.06
            }
        }()

        // Leverage: who needs whom.
        var leverage = 0.0
        let peak = player.position.peakAgeRange
        if player.age > peak.upperBound {
            // Every year past the window costs him a negotiating position.
            leverage -= Swift.min(0.15, Double(player.age - peak.upperBound) * 0.04)
        } else if player.age >= peak.lowerBound {
            leverage += 0.03
        } else {
            leverage -= 0.03      // still unproven; the club holds the cards
        }
        if situation.cameOffCareerYear { leverage += 0.06 }
        // The tag window. A tagged man has been told what he is worth for one
        // year and has every reason to charge for the next five.
        if player.isFranchiseTagged { leverage += 0.08 }
        if player.isHoldingOut { leverage += 0.05 }

        // The club itself. A losing building pays a premium to keep anybody who
        // is not motivated by winning; a contender is its own argument.
        var team = 0.0
        if situation.weeksPlayed >= 6 {
            if situation.teamWinPercentage < 0.35 { team += 0.05 }
            else if situation.isContender { team -= 0.03 }
        }

        return ContractDemand.SituationBreakdown(components: [
            .init(source: .agentPersona, value: agent),
            .init(source: .archetype, value: archetype),
            .init(source: .motivation, value: motivationRaw),
            .init(source: .morale, value: morale),
            .init(source: .motivationState, value: state),
            .init(source: .leverage, value: leverage),
            .init(source: .teamSituation, value: team),
            .init(source: .frontOffice, value: gm.total),
        ])
    }

    // MARK: - Floor

    /// The share of his standing ask an agent will actually take.
    ///
    /// Persona sets the level (a hardliner leaves himself 10 % of room, a
    /// deal-maker 20 %) and leverage tilts it: a man with none has to take less
    /// than his agent's usual floor, and a man with all of it does not have to.
    private static func floorFraction(
        player: Player,
        persona: AgentPersona,
        situation: NegotiationSituation
    ) -> Double {
        var base: Double = {
            switch persona {
            case .hardliner:   return 0.86
            case .cooperative: return 0.78
            case .loyalist:    return 0.82
            }
        }()
        let peak = player.position.peakAgeRange
        if player.age > peak.upperBound + 1 { base -= 0.05 }
        if player.overall < 70 { base -= 0.03 }
        if player.overall >= 88 { base += 0.03 }
        if situation.cameOffCareerYear { base += 0.02 }
        return Swift.min(0.95, Swift.max(0.72, base))
    }

    // MARK: - Refusal

    /// Whether this client will come to the table at all, and why not.
    ///
    /// Two sources, in order. First the shared stance model
    /// (`AgentRefusalReason.evaluate`) — benched, wants out, riding into
    /// retirement, losing culture — which is deliberately the chat layer's
    /// vocabulary so the badge, the opening line and this verdict cannot
    /// disagree. Then one economy-owned addition the stance model has no inputs
    /// for: **a mercenary will not sign up to lose for a front office he does
    /// not rate.** That second door opens wider the worse the GM's standing is,
    /// which is the "bad GM gets more refusals" half of the brief.
    static func refusalVerdict(
        player: Player,
        situation: NegotiationSituation,
        gm: GMAdjustment
    ) -> AgentRefusalReason? {
        if let stance = AgentRefusalReason.evaluate(
            playerID: player.id,
            season: situation.season,
            age: player.age,
            morale: player.morale,
            gamesStartedThisSeason: player.gamesStartedThisSeason,
            loyaltyYears: player.loyaltyYears,
            teamWins: situation.teamWins,
            teamLosses: situation.teamLosses,
            weeksPlayed: situation.weeksPlayed
        ) {
            return stance
        }

        let isMercenary = player.personality.motivation == .money
            || player.personality.archetype == .loneWolf
        guard isMercenary,
              situation.weeksPlayed >= 6,
              situation.teamWinPercentage < 0.35
        else { return nil }

        // 18 % at a neutral front office, rising toward 48 % at the worst one
        // the GM factor can produce. Deterministic, on a salt no other agent
        // trait uses, so the answer does not change between two openings of the
        // same conversation — but salted by the season as well, so a door that
        // closed one league year is not closed for the rest of his career.
        let threshold = 0.18 + Swift.max(0, gm.total) * 2.0
        let salt = 0xA7 ^ (UInt64(bitPattern: Int64(situation.season)) &* 0x9E37_79B9_7F4A_7C15)
        return unitDraw(player.id, salt: salt) < threshold ? .losingCulture : nil
    }

    // MARK: - Structure Preferences

    /// Opening frame for an agent who IS willing to talk.
    private static func openingTone(persona: AgentPersona, player: Player) -> AgentToneKey {
        switch persona {
        case .hardliner:   return .hardline
        case .cooperative: return player.morale >= 75 ? .eager : .professional
        case .loyalist:    return player.loyaltyYears >= 3 ? .eager : .professional
        }
    }

    /// A prove-it deal is a bet, not a concession: a man whose market has just
    /// been marked down takes one year, plays well, and comes back at a price
    /// this contract could not have got him.
    private static func wantsProveItDeal(player: Player, situation: NegotiationSituation) -> Bool {
        if player.motivationState == .driven && player.age <= 29 && player.morale < 70 { return true }
        if player.morale < 45 { return true }
        let peak = player.position.peakAgeRange
        if player.age > peak.upperBound + 2 && !situation.cameOffCareerYear { return true }
        return false
    }

    private static func preferredYears(player: Player, isProveIt: Bool) -> Int {
        let ageMax = maxContractYears(forAge: player.age)
        guard !isProveIt else { return min(2, ageMax) }
        let draw = unitDraw(player.id, salt: 0x2D)
        let span: ClosedRange<Int> = {
            switch player.age {
            case ...25:   return 3...4
            case 26...29: return 3...5
            case 30...31: return 2...4
            case 32...33: return 2...3
            default:      return 1...2
            }
        }()
        let width = span.upperBound - span.lowerBound
        let step = min(width, Int(draw * Double(width + 1)))
        return min(span.lowerBound + step, ageMax)
    }

    private static func preferredGuaranteedPercent(player: Player, persona: AgentPersona) -> Int {
        let draw = unitDraw(player.id, salt: 0x6B)
        let span: ClosedRange<Int> = {
            switch player.overall {
            case 90...:   return 60...80
            case 80..<90: return 45...65
            case 70..<80: return 30...50
            default:      return 20...35
            }
        }()
        let width = span.upperBound - span.lowerBound
        let base = span.lowerBound + Int(draw * Double(width))
        // A hardliner does not only want more money, he wants more of it
        // written down.
        let shift = persona == .hardliner ? 5 : (persona == .cooperative ? -3 : 0)
        return max(10, min(95, base + shift))
    }

    // MARK: - Deterministic Draws

    /// A stable 0…1 draw for one player, salted so two traits keyed on the same
    /// UUID do not move together.
    ///
    /// FNV-1a over all sixteen bytes rather than `hashValue`: Swift's hashing is
    /// re-seeded every launch, which would re-roll a "deterministic" trait on
    /// every app start — the exact bug `AgentPersona.forPlayer` documents.
    private static func unitDraw(_ id: UUID, salt: UInt64) -> Double {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return Double(hash % 10_000) / 10_000.0
    }

    private static func clamp(_ value: Double, _ limit: Double) -> Double {
        Swift.min(limit, Swift.max(-limit, value))
    }

    // MARK: - Generate Agent's Opening Demand

    /// Creates the agent's initial asking price based on player profile.
    ///
    /// Thin wrapper over ``demand(player:negotiationType:salaryCap:situation:standing:)``
    /// kept for the callers that only want an offer and a line. Everything
    /// numeric now comes from the demand model, so the sheet, the chat and the
    /// AI market cannot quote three different prices for one man.
    ///
    /// The opening ask carries **no incentives** (TODO §5.5), and that is the
    /// design rather than an omission: no agent opens by asking to be paid
    /// conditionally. Clauses are the GM's instrument for closing a gap he
    /// cannot close with guaranteed money, so they enter the conversation from
    /// his side — and how much they buy him depends entirely on who is across
    /// the table (`ContractEngine.personaIncentiveCredit`).
    /// `teamCapSpace` is deliberately NOT a parameter. It was one, threaded
    /// through four call sites into a body that ignored it, which read as a cap
    /// gate that did not exist. An agent's ask does not depend on the buyer's
    /// room — what a club can afford is a constraint on the OFFER, and it is
    /// enforced where offers are made (`ContractNegotiationView`'s composer).
    static func generateOpeningDemand(
        player: Player,
        negotiationType: NegotiationType,
        salaryCap: Int = 265_000,
        situation: NegotiationSituation = .neutral,
        standing: GMStanding = .neutral
    ) -> (offer: NegotiationOffer, message: String, demand: ContractDemand) {
        let opening = demand(
            player: player, negotiationType: negotiationType,
            salaryCap: salaryCap, situation: situation, standing: standing
        )
        let offer = opening.openingOffer
        let message = generateOpeningMessage(player: player, offer: offer, type: negotiationType)
        return (offer, message, opening)
    }

    // MARK: - Age-Based Max Contract Years

    /// Maximum contract years a player will accept based on age.
    /// Older players approaching retirement won't sign long-term deals.
    static func maxContractYears(forAge age: Int) -> Int {
        switch age {
        case 34...: return 2   // 34+: max 1-2 years
        case 32...33: return 3 // 32-33: max 2-3 years
        case 30...31: return 4 // 30-31: max 3-4 years
        default: return 6      // Under 30: any length
        }
    }

    // MARK: - Agent Response

    /// One graded offer: the verdict, the number that goes back across the
    /// table, and the demand as it stands afterwards.
    ///
    /// The chat layer keeps `demand` and feeds it into the next call — that is
    /// how the insult ratchet survives a round. Nothing here is a string: the
    /// tone is the key the dialogue is looked up by.
    struct AgentResponse {
        let tone: AgentToneKey
        let counterOffer: NegotiationOffer?
        let outcome: NegotiationOutcome
        /// The demand AFTER grading — ratcheted if the offer was an insult,
        /// otherwise unchanged.
        let demand: ContractDemand
        /// The offer was rejected on LENGTH, not money. The chat says something
        /// different about a five-year deal for a 34-year-old than about a
        /// lowball, and it cannot tell them apart from the tone alone.
        let isYearsPushback: Bool
        /// The agent's own number this round, per year — what the counter card
        /// and the sentence both have to quote.
        let counterPerYear: Int
    }

    /// **Grade one GM offer against the demand model.**
    ///
    /// The only place an offer is judged. Note what is deliberately NOT here
    /// any more: morale, loyalty and persona used to be re-applied to the
    /// offer/ask ratio at this point, on top of already being in the ask. That
    /// double-counted every one of them — a loyalist on an extension was
    /// getting his discount twice, which is why a 3 %-under offer to a happy
    /// club veteran read as a full-price acceptance. They live in
    /// ``ContractDemand`` now, once.
    ///
    /// - Parameter recordToLedger: writes the outcome to
    ///   ``NegotiationLedger``. Off for previews and sweeps, on for the game.
    static func respond(
        gmOffer: NegotiationOffer,
        player: Player,
        demand: ContractDemand,
        previousAgentOffer: NegotiationOffer,
        roundNumber: Int,
        recordToLedger: Bool = true
    ) -> AgentResponse {
        // A client who will not talk cannot be negotiated into talking.
        guard !demand.isRefusing else {
            return AgentResponse(
                tone: .refusing, counterOffer: nil, outcome: .playerWalked,
                demand: demand, isYearsPushback: false,
                counterPerYear: previousAgentOffer.annualCapHit
            )
        }

        let persona = demand.persona

        // Length is a separate conversation from money: no agent signs his
        // 34-year-old to five years, whatever the number on it is.
        let maxYears = maxContractYears(forAge: player.age)
        if gmOffer.years > maxYears {
            let adjusted = NegotiationOffer(
                years: maxYears,
                annualSalary: previousAgentOffer.annualSalary,
                signingBonus: previousAgentOffer.signingBonus,
                guaranteedPercent: previousAgentOffer.guaranteedPercent,
                noTradeClause: previousAgentOffer.noTradeClause,
                // Shortening the deal is not a reason to drop the clauses the
                // GM already put on it.
                incentives: gmOffer.incentives
            )
            return AgentResponse(
                tone: .professional, counterOffer: adjusted, outcome: .pending,
                demand: demand, isYearsPushback: true,
                counterPerYear: adjusted.annualCapHit
            )
        }

        let standingAsk = max(1, previousAgentOffer.annualCapHit)

        // §5.5: clauses count toward the offer at the agent's own discount, per
        // year, so they land on the same scale the thresholds are written in.
        let years = max(1, gmOffer.years)
        let creditedPerYear = ContractEngine.creditedIncentiveValue(
            gmOffer.incentives, player: player, persona: persona, years: years
        ) / years

        // Guarantees are the other half of an offer. A number that matches the
        // ask on paper but guarantees 20 points less of it is not the same
        // offer, and an agent prices that gap rather than ignoring it.
        let guaranteeGap = previousAgentOffer.guaranteedPercent - gmOffer.guaranteedPercent
        let guaranteeDrag = guaranteeGap > 15 ? 0.96 : 1.0

        let effectivePerYear = Int(Double(gmOffer.annualCapHit + creditedPerYear) * guaranteeDrag)
        let tone = demand.tone(forPerYear: effectivePerYear, currentAskPerYear: standingAsk)

        switch tone {
        case .eager:
            if recordToLedger { NegotiationLedger.recordSigning(tone: .eager) }
            return AgentResponse(
                tone: .eager, counterOffer: nil, outcome: .dealReached(gmOffer),
                demand: demand, isYearsPushback: false, counterPerYear: standingAsk
            )

        case .insulted:
            // R22 preserved: a hardliner does not counter a lowball, he hangs
            // up for the offseason.
            if persona.breaksOffForSeason {
                if recordToLedger { NegotiationLedger.recordBreakOff() }
                return AgentResponse(
                    tone: .insulted, counterOffer: nil, outcome: .negotiationsBrokenOff,
                    demand: demand, isYearsPushback: false, counterPerYear: standingAsk
                )
            }
            if recordToLedger { NegotiationLedger.recordInsult() }
            // The ask moves the WRONG way, and one round of patience is gone.
            let escalated = demand.escalated()
            let ratchetedAsk = ratcheted(previousAgentOffer)
            let counter = generateCompromise(
                gmOffer: gmOffer,
                agentAsk: ratchetedAsk,
                splitFactor: 1.0,           // he does not move toward the offer at all
                player: player,
                persona: persona
            )
            return AgentResponse(
                tone: .insulted, counterOffer: counter, outcome: .pending,
                demand: escalated, isYearsPushback: false,
                counterPerYear: counter.annualCapHit
            )

        case .hardline, .professional, .refusing:
            // Patience is spent on the round the GM has just used, so it is
            // checked after the deal-closing and insult branches: an offer that
            // would have signed still signs on the last round.
            if roundNumber >= demand.maxRounds {
                if recordToLedger { NegotiationLedger.recordWalkAway() }
                return AgentResponse(
                    tone: tone, counterOffer: nil, outcome: .playerWalked,
                    demand: demand, isYearsPushback: false, counterPerYear: standingAsk
                )
            }
            // How far he comes toward the GM: most of the way when the offer is
            // already past his floor, barely at all when it is not.
            let split = tone == .professional ? 0.60 : 0.80
            let counter = generateCompromise(
                gmOffer: gmOffer,
                agentAsk: previousAgentOffer,
                splitFactor: split,
                player: player,
                persona: persona,
                // §5.5: this close, an agent who believes in clauses will bridge
                // the last of the gap with them himself. A hardliner never does.
                proposeIncentives: tone == .professional && persona != .hardliner
            )
            return AgentResponse(
                tone: tone, counterOffer: counter, outcome: .pending,
                demand: demand, isYearsPushback: false,
                counterPerYear: counter.annualCapHit
            )
        }
    }

    /// The same ask, 6 % dearer — what a lowball buys the GM.
    private static func ratcheted(_ offer: NegotiationOffer) -> NegotiationOffer {
        NegotiationOffer(
            years: offer.years,
            annualSalary: Int(Double(offer.annualSalary) * insultRatchet),
            signingBonus: Int(Double(offer.signingBonus) * insultRatchet),
            guaranteedPercent: min(95, offer.guaranteedPercent + 3),
            noTradeClause: offer.noTradeClause,
            incentives: offer.incentives
        )
    }

    // MARK: - Evaluate Counter Offer (chat surface)

    /// One graded round, in the shape a chat layer needs.
    ///
    /// **The tone is in here for a reason.** The old return was a three-tuple
    /// that dropped `AgentResponse.tone` on the floor, so the chat re-derived a
    /// tone of its own — on `totalValue` instead of the per-year cap hit the
    /// engine grades — and the two disagreed constantly: a 2-year $38M answer to
    /// a 4-year $40M ask graded `.professional` in the engine (0.95 per year)
    /// and rendered as a red `.insulted` bubble with an "Ask hardened" chip for a
    /// hardening that never happened. The engine owns the verdict AND the frame
    /// it is spoken in; the chat owns only the words.
    struct ChatVerdict {
        let message: String
        let counterOffer: NegotiationOffer?
        let outcome: NegotiationOutcome
        /// The frame the agent is in — what the bubble, the chip and the border
        /// all key off.
        let tone: AgentToneKey
        /// Lowballs absorbed INCLUDING this round. The caller persists it and
        /// hands it back, which is what makes the patience cost survive a round.
        let insultCount: Int
        /// The demand as it stands after grading.
        let demand: ContractDemand
        /// Rejected on LENGTH rather than money.
        let isYearsPushback: Bool
    }

    /// Agent evaluates the GM's counter-offer and responds.
    ///
    /// A thin shell over
    /// ``respond(gmOffer:player:demand:previousAgentOffer:roundNumber:recordToLedger:)``
    /// — the verdict, the counter, the tone and the ledger write all come from
    /// there, so the composer and the transcript cannot reach different
    /// conclusions about the same offer.
    static func evaluateCounterOffer(
        gmOffer: NegotiationOffer,
        player: Player,
        previousAgentOffer: NegotiationOffer,
        roundNumber: Int,
        negotiationType: NegotiationType,
        salaryCap: Int = 265_000,
        situation: NegotiationSituation = .neutral,
        standing: GMStanding = .neutral,
        insultCount: Int = 0
    ) -> ChatVerdict {
        let currentDemand = demand(
            player: player, negotiationType: negotiationType,
            salaryCap: salaryCap, situation: situation, standing: standing,
            insultCount: insultCount
        )
        let response = respond(
            gmOffer: gmOffer, player: player, demand: currentDemand,
            previousAgentOffer: previousAgentOffer, roundNumber: roundNumber
        )

        func verdict(_ message: String) -> ChatVerdict {
            ChatVerdict(
                message: message,
                counterOffer: response.counterOffer,
                outcome: response.outcome,
                tone: response.tone,
                insultCount: response.demand.insultCount,
                demand: response.demand,
                isYearsPushback: response.isYearsPushback
            )
        }

        if response.isYearsPushback {
            let maxYears = maxContractYears(forAge: player.age)
            return verdict("At \(player.age) years old, \(player.firstName) isn't looking for a \(gmOffer.years)-year commitment. We'd consider \(maxYears) years max. Here's our revised ask.")
        }

        switch response.outcome {
        case .dealReached(let offer):
            return verdict(generateAcceptMessage(player: player, offer: offer))
        case .negotiationsBrokenOff:
            return verdict(generateBreakOffMessage(player: player))
        case .playerWalked:
            let ratio = Double(gmOffer.annualCapHit) / Double(max(1, previousAgentOffer.annualCapHit))
            return verdict(generateWalkAwayMessage(player: player, ratio: ratio))
        case .pending, .walkedAway:
            let legacyTone: Tone = {
                switch response.tone {
                case .insulted:  return .insulted
                case .hardline:  return .disappointed
                default:         return .reasonable
                }
            }()
            return verdict(generateCounterMessage(
                player: player, persona: response.demand.persona, tone: legacyTone,
                round: roundNumber, counter: response.counterOffer, gmOffer: gmOffer
            ))
        }
    }

    // MARK: - Compromise Generator

    private static func generateCompromise(
        gmOffer: NegotiationOffer,
        agentAsk: NegotiationOffer,
        splitFactor: Double,  // 0.5 = meet in middle, 0.8 = agent barely moves
        player: Player,
        persona: AgentPersona,
        proposeIncentives: Bool = false
    ) -> NegotiationOffer {
        let salary = Int(Double(agentAsk.annualSalary) * splitFactor + Double(gmOffer.annualSalary) * (1.0 - splitFactor))
        let bonus = Int(Double(agentAsk.signingBonus) * splitFactor + Double(gmOffer.signingBonus) * (1.0 - splitFactor))
        let guaranteed = Int(Double(agentAsk.guaranteedPercent) * splitFactor + Double(gmOffer.guaranteedPercent) * (1.0 - splitFactor))

        // Years: agent usually holds firm on years
        let years = agentAsk.years

        // §5.5: the counter keeps whatever clauses the GM put on the table —
        // the agent is arguing about the money, not tearing up the structure.
        // Only when the GM used none, the gap is nearly closed and the persona
        // believes in clauses does the agent write them himself.
        var incentives = gmOffer.incentives
        if incentives.isEmpty, proposeIncentives {
            incentives = ContractEngine.suggestedIncentives(
                player: player,
                annualSalaryK: salary,
                limit: persona == .cooperative ? 2 : 1
            )
        }

        return NegotiationOffer(
            years: years,
            annualSalary: salary,
            signingBonus: bonus,
            guaranteedPercent: min(100, guaranteed),
            noTradeClause: agentAsk.noTradeClause,
            incentives: incentives
        )
    }

    // MARK: - Message Generation

    private enum Tone { case reasonable, disappointed, insulted }

    private static func generateOpeningMessage(player: Player, offer: NegotiationOffer, type: NegotiationType) -> String {
        let name = player.firstName
        let salaryM = formatMillions(offer.annualSalary)
        let totalM = formatMillions(offer.totalValue)
        let bonusM = formatMillions(offer.signingBonus)

        switch type {
        case .extend:
            let messages = [
                "\(name) loves it here and wants to stay, but we need the deal to reflect his value. We're looking at \(offer.years) years, \(salaryM)/year with a \(bonusM) signing bonus.",
                "My client has been loyal to this organization. A \(offer.years)-year extension worth \(totalM) total with \(offer.guaranteedPercent)% guaranteed would keep him here long-term.",
                "Let's get this done. \(name) is open to extending — \(offer.years) years at \(salaryM) per year, \(bonusM) bonus, \(offer.guaranteedPercent)% guaranteed."
            ]
            return messages.randomElement()!
        case .freeAgent:
            let messages = [
                "\(name) has several teams interested. To bring him to your organization, we'd need \(offer.years) years at \(salaryM)/year with \(bonusM) up front.",
                "The market for \(name) is strong. We're looking for \(totalM) total over \(offer.years) years with \(offer.guaranteedPercent)% guaranteed.",
                "\(name) is excited about the opportunity here, but the numbers need to be right. \(offer.years) years, \(salaryM) per, \(bonusM) signing bonus."
            ]
            return messages.randomElement()!
        }
    }

    private static func generateCounterMessage(
        player: Player,
        persona: AgentPersona,
        tone: Tone,
        round: Int,
        counter: NegotiationOffer? = nil,
        gmOffer: NegotiationOffer? = nil
    ) -> String {
        let body = counterBody(player: player, persona: persona, tone: tone, round: round)
        guard let remark = incentiveRemark(
            player: player,
            persona: persona,
            counter: counter,
            gmOffer: gmOffer
        ) else { return body }
        return "\(body) \(remark)"
    }

    /// §5.5: the agent's line about the clauses on the table. Says out loud what
    /// `ContractEngine.personaIncentiveCredit` does quietly, so a GM can learn
    /// which agents incentives work on without reading the engine.
    private static func incentiveRemark(
        player: Player,
        persona: AgentPersona,
        counter: NegotiationOffer?,
        gmOffer: NegotiationOffer?
    ) -> String? {
        let name = player.firstName
        let gmClauses = gmOffer?.incentives ?? []
        let counterClauses = counter?.incentives ?? []

        // The agent volunteered clauses the GM had not offered.
        if gmClauses.isEmpty, let lead = counterClauses.first {
            return "We've written in \(lead.summary) to bridge the rest — \(name) will earn it."
        }

        guard !gmClauses.isEmpty else { return nil }

        switch persona {
        case .hardliner:
            return "And spare us the escalators. \(name) gets hurt, \(name) gets benched, that money evaporates. Guarantee it or don't offer it."
        case .cooperative:
            let credited = ContractEngine.creditedIncentiveValue(
                gmClauses, player: player, persona: persona, years: max(1, gmOffer?.years ?? 1)
            )
            return "The incentives help — we're counting them as about \(formatMillions(credited)) of real money."
        case .loyalist:
            return "\(name) will take the clauses. He backs himself in this building."
        }
    }

    private static func counterBody(player: Player, persona: AgentPersona, tone: Tone, round: Int) -> String {
        let name = player.firstName
        switch tone {
        case .reasonable:
            let msgs: [String]
            switch persona {
            case .hardliner:
                msgs = [
                    "That's movement, but \(name) wants starter money. Here's where the deal gets done.",
                    "Closer. We're not here to haggle forever — this number closes it today.",
                    "We appreciate the effort. One more push and \(name) signs."
                ]
            case .cooperative:
                msgs = [
                    "We appreciate the offer. We're getting closer — here's where we can meet you.",
                    "\(name) wants to make this work. We've adjusted our ask. Take a look.",
                    "Good progress. Here's a revised number that works for both sides."
                ]
            case .loyalist:
                msgs = [
                    "\(name) loves this locker room. He's already taking a discount to stay — meet us here.",
                    "He wants to retire in this uniform. Show him the respect and this is done.",
                    "We've shaved our ask because \(name) values what you've built. This is fair."
                ]
            }
            return msgs.randomElement()!
        case .disappointed:
            let msgs: [String]
            switch persona {
            case .hardliner:
                msgs = [
                    "That's below what \(name) is worth and you know it. This is our floor — take it seriously.",
                    "\(name) wants starter money, not a hometown haircut. My patience has limits.",
                    "We've come down once. We won't keep chasing you. Here's the number."
                ]
            case .cooperative:
                msgs = [
                    "Honestly, we expected more given \(name)'s production. Here's our bottom line.",
                    "That's below what the market bears. We've come down, but there's a floor here.",
                    "\(name) is disappointed but willing to negotiate. This is our revised ask."
                ]
            case .loyalist:
                msgs = [
                    "\(name) took a discount to stay before. He won't be taken for granted twice.",
                    "Loyalty runs both ways. He's hurt, but he still wants this to work — here's our ask.",
                    "He's given this team everything. Reward that, and we sign today."
                ]
            }
            return msgs.randomElement()!
        case .insulted:
            let msgs = [
                "With all due respect, that offer doesn't reflect \(name)'s value at all. We need to see significant movement.",
                "We can't take that back to \(name). If you're serious about keeping him, here's what it takes.",
                "That's a non-starter. \(name) has options. Show us you're serious."
            ]
            return msgs.randomElement()!
        }
    }

    /// R22: hardliner break-off — talks are over for the offseason.
    private static func generateBreakOffMessage(player: Player) -> String {
        let name = player.firstName
        let msgs = [
            "That offer is an insult. Don't call us again this offseason — \(name) is done talking.",
            "You just told \(name) exactly what you think of him. We're out. Talks are over until next year.",
            "Unbelievable. We're ending negotiations here. \(name)'s camp won't return calls this offseason."
        ]
        return msgs.randomElement()!
    }

    private static func generateAcceptMessage(player: Player, offer: NegotiationOffer) -> String {
        let name = player.firstName
        let totalM = formatMillions(offer.totalValue)
        let msgs = [
            "\(name) is thrilled to stay. \(offer.years) years, \(totalM) total — we have a deal!",
            "We're happy with this. \(name) can't wait to get back to work. Deal done!",
            "That works for us. \(name) is committed to this team. Let's make it official."
        ]
        let base = msgs.randomElement()!
        guard !offer.incentives.isEmpty else { return base }
        // §5.5: name the ceiling, so the GM leaves knowing what he might owe.
        return "\(base) With the clauses he can push it to \(formatMillions(offer.maxValue))."
    }

    private static func generateWalkAwayMessage(player: Player, ratio: Double) -> String {
        let name = player.firstName
        if ratio < 0.65 {
            let msgs = [
                "\(name) feels disrespected by this organization. We're exploring other options.",
                "We're done here. The gap is too large. \(name) will test the open market.",
                "This isn't going to work. \(name) deserves better."
            ]
            return msgs.randomElement()!
        } else {
            let msgs = [
                "We've gone back and forth enough. \(name) has decided to move on.",
                "Unfortunately we couldn't find common ground. \(name) wishes the team well.",
                "The negotiations have stalled. \(name) will explore his options."
            ]
            return msgs.randomElement()!
        }
    }

    // MARK: - Formatting Helper

    private static func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}
