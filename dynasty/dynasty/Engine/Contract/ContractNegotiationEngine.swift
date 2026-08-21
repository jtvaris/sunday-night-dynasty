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

enum AgentNegotiationOutcome {
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
    /// **Asking a man already under contract to take less.** The cap-compliance
    /// lever, not a third way to buy a player.
    ///
    /// It is a `NegotiationType` rather than a separate screen because
    /// everything around the ask is identical to an extension: it is the club's
    /// own player, the same agent takes the call, the same refusal model decides
    /// whether he is at the table at all, and the same transcript records it.
    /// What differs is only the direction of the money, and that lives in
    /// ``ContractNegotiationEngine/payCutVerdict(player:demand:currentSalary:proposedSalary:situation:)``
    /// — a consent model, not a bid/counter loop.
    ///
    /// **Every economic branch treats `payCut` exactly as `extend`.** The demand
    /// model's `isOwnClub` and its refusal gate both test `!= .freeAgent` for
    /// that reason: a pay-cut conversation must price the man identically to the
    /// extension conversation it is an alternative to, or the workspace would
    /// quote one market value and the Contact Agent chat another.
    case payCut

    /// True for both conversations the club has with its OWN player.
    var isOwnClub: Bool { self != .freeAgent }
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
    ///
    /// Defined in ONE place — `ContractNegotiationEngine.isContender(wins:losses:)`
    /// — because three systems now turn on it (the legacy veteran's discount,
    /// the ring-chaser's exit condition, the team term in the breakdown) and a
    /// second definition living in a View would mean the chat could call a club
    /// a contender while the stance model called it a loser.
    var isContender: Bool = false
    /// He is coming off the best season of his career and both sides know it.
    var cameOffCareerYear: Bool = false
    /// **He took a prove-it deal and won the bet.**
    ///
    /// The other half of the prove-it story, and the reason a short deal is a
    /// decision rather than a free discount: a man who signed one year to
    /// rebuild his market and then played like it comes back to the table
    /// holding the receipts. Set by
    /// `ContractNegotiationEngine.situation(for:…)` from the persisted
    /// `ProveItRegistry` plus a season that beat expectation; the neutral
    /// identity is `false`, so nothing in the AI market can be moved by it.
    var provedTheBet: Bool = false

    static let neutral = NegotiationSituation()
}

// MARK: - Negotiation Stance

/// The situation-driven character of one negotiation.
///
/// Three cases the money alone cannot express, each with its own trigger, its
/// own exit and its own eligibility gate:
///
/// | stance | trigger | what it does | exit |
/// |---|---|---|---|
/// | ``ringChaser`` | 88+ OVR, fiercely competitive, club going nowhere | refuses at ANY price, may demand a trade | the club becomes a contender |
/// | ``legacyVeteran`` | 33+, 82+ OVR | discounts hard for a contender; as an FA walks away from a loser for less money | ceases when he is no longer elite |
/// | ``proveIt`` | market marked down (crashed value, low morale, past peak) | takes a short, clause-heavy bet readily | he plays the season |
/// | ``provenBet`` | won the prove-it bet last year | opens hardline: "I bet on myself and won" | the deal gets done |
///
/// Raw-string backed for the same migration-safety reason `AgentToneKey` is:
/// a persisted transcript must still decode when this vocabulary grows.
enum NegotiationStance: String, Codable, CaseIterable {
    case ringChaser
    case legacyVeteran
    case proveIt
    case provenBet

    /// One line for the chat header / roster row.
    var label: String {
        switch self {
        case .ringChaser:    return "Chasing a ring"
        case .legacyVeteran: return "Legacy veteran"
        case .proveIt:       return "Betting on himself"
        case .provenBet:     return "Won his bet"
        }
    }
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
    /// The situation-driven character of this negotiation, when it has one.
    ///
    /// Not a fifth tone and not a second refusal: a stance is the *story* the
    /// numbers are already telling, named so the chat can say it out loud. All
    /// three are derived from the same inputs the money is, so nothing here can
    /// disagree with the ask.
    let stance: NegotiationStance?

    /// No offer this club can write will be accepted. Distinct from
    /// ``isRefusing``, which merely means he is not at the table today.
    var neverSigns: Bool { refusalReason?.neverSignsAtAnyPrice == true }

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
            stance: stance,
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
    ///
    /// Also what one round of PESTERING costs — an offer tabled at a man who
    /// has already said the number is not the problem rides the same ratchet,
    /// deliberately, so the two ways of not listening cost the same.
    static let insultRatchet = 1.06

    // MARK: - Stance Tuning
    //
    // The eligibility gates and prices for the three situation-driven stances,
    // in one block so the rarity budget is auditable in one read rather than
    // spread across five functions. See `stanceCensus` to measure the result
    // against a real league instead of against this arithmetic.

    /// Rating floor for a ring-chaser. 88 is roughly the top 2.5 % of a
    /// calibrated league — the tier where a man is genuinely the reason a team
    /// might win, and therefore genuinely entitled to be angry that it does not.
    static let ringChaserOverallGate = 88

    /// Competitiveness floor. `Player.competitiveness` sits at 55 by default, so
    /// 80 selects the men the trait is actually about rather than everyone who
    /// dislikes losing (which is everyone).
    static let ringChaserCompetitivenessGate = 80

    /// The tiebreak draw among the handful who clear every structural gate.
    /// Not season-salted: see `ringChaserVerdict` for why a never-sign stance
    /// must persist until its stated exit condition is met.
    static let ringChaserDraw = 0.5

    /// A legacy veteran is old AND still elite. Old alone is a decline story;
    /// this is the other one.
    static let legacyVeteranAgeGate = 33
    static let legacyVeteranOverallGate = 82

    /// What an aging great knocks off his ask to play for a contender. Stacks
    /// with the `.winning` motivation discount rather than replacing it — a man
    /// can be both, and Brady was.
    static let legacyVeteranDiscount = 0.10

    /// What winning a prove-it bet is worth on the next ask. Large on purpose:
    /// it is the entire reason a player would take one year instead of four,
    /// and a premium the club can shrug off makes the short deal a free option.
    static let provenBetPremium = 0.10

    /// Extra weight a prove-it client puts on performance clauses. He is not
    /// being paid for last season, he is being paid for the next one — so
    /// money that only arrives if he is right is money he was going to bet on
    /// anyway.
    static let proveItIncentiveCredit = 1.35

    /// What a prove-it client will shave for a genuinely short deal. He wants
    /// back on the market; a one- or two-year term is part of the price he is
    /// paying for that, not a concession the club has to buy.
    static let proveItShortDealCredit = 1.05

    /// Morale a player loses each time the club tables an offer his agent has
    /// already declined to consider. Small, and it has to be: pestering is
    /// rude, not career-altering, and the real cost is the ratcheting ask.
    static let pesterMoraleCost = 1

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
        salaryCap: Int,
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
        let minimum = veteranMinimum(salaryCap: salaryCap)
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
        // D4-C: one stance is NOT extension-only, and treating it as one is why
        // there was no "won't sign with a loser" gate in the market where it
        // matters most. `.benched`, `.wantsOut` and `.ridingIntoRetirement` are
        // all statements about the club he is ALREADY at, and a free agent has
        // none of them to make. `.losingCulture` is a statement about the club
        // doing the asking, and it is the oldest sentence in free agency.
        let refusal: AgentRefusalReason? = negotiationType.isOwnClub
            ? refusalVerdict(player: player, situation: situation, gm: gm)
            : freeAgentRefusalVerdict(player: player, situation: situation)
        let proveIt = wantsProveItDeal(player: player, situation: situation)
        let stance = self.stance(
            player: player, situation: situation, refusal: refusal, isProveIt: proveIt
        )

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
            personaTone: refusal == nil
                ? openingTone(persona: persona, player: player, situation: situation)
                : .refusing,
            refusalReason: refusal,
            stance: stance,
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
    ///
    /// `isContender` is a parameter rather than a computed value only so a
    /// caller that knows better (a playoff seed, a division lead) can overrule
    /// the record; leaving it out gets ``isContender(wins:losses:)``, which is
    /// the definition every other part of this model uses.
    static func situation(
        for player: Player,
        season: Int = 0,
        teamWins: Int = 0,
        teamLosses: Int = 0,
        weeksPlayed: Int = 0,
        isContender: Bool? = nil
    ) -> NegotiationSituation {
        let played = max(0, teamWins + teamLosses)
        // A career year, from what a `Player` row actually knows: he started
        // essentially every game and the building is happy with him. It is a
        // proxy, and a deliberately conservative one — a caller holding real
        // `PlayerSeasonHistory` should overwrite it.
        let careerYear = player.gamesStartedThisSeason >= 15 && player.morale >= 70
        return NegotiationSituation(
            season: season,
            teamWinPercentage: played == 0 ? 0.5 : Double(teamWins) / Double(played),
            teamWins: teamWins,
            teamLosses: teamLosses,
            weeksPlayed: weeksPlayed,
            isContender: isContender ?? self.isContender(wins: teamWins, losses: teamLosses),
            cameOffCareerYear: careerYear,
            // The prove-it bet is settled here rather than in the demand model
            // because it is the one input that is a FACT about the save (he
            // signed that deal, in that league year) rather than a property of
            // the player row. The bet only counts once the season it bought has
            // actually been played, and only if he beat expectation in it.
            provedTheBet: ProveItRegistry.betSeason(player.id).map { $0 < season } == true
                && careerYear
        )
    }

    // MARK: - Contender

    /// **The one definition of a contender**, so the ring-chaser's exit
    /// condition, the legacy veteran's discount and the team term in the
    /// breakdown cannot disagree about the same club.
    ///
    /// Two thirds of the games won, once at least six have been played. Record
    /// rather than projection on purpose: the men in this model are reacting to
    /// what they have watched, not to a simulation's opinion of what comes next.
    static func isContender(wins: Int, losses: Int) -> Bool {
        let played = wins + losses
        guard played >= 6 else { return false }
        return Double(wins) / Double(played) >= 0.65
    }

    /// The mirror: a record a player reads as "this is not going anywhere".
    /// Deliberately NOT `!isContender` — most clubs are neither, and a .500 team
    /// in October is not something a man demands out of.
    static func isGoingNowhere(wins: Int, losses: Int) -> Bool {
        let played = wins + losses
        guard played >= 6 else { return false }
        return Double(wins) / Double(played) < 0.45
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
        let isOwnClub = negotiationType.isOwnClub

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
        // He took the short deal, played the season, and was right. The premium
        // is the point of the mechanic: a prove-it contract that costs the club
        // nothing when the bet lands is not a bet, it is a discount with extra
        // steps.
        if situation.provedTheBet { leverage += provenBetPremium }

        // The club itself. A losing building pays a premium to keep anybody who
        // is not motivated by winning; a contender is its own argument.
        var team = 0.0
        if situation.weeksPlayed >= 6 {
            if situation.teamWinPercentage < 0.35 { team += 0.05 }
            else if situation.isContender { team -= 0.03 }

            // **The legacy clause.** An aging great on a contender takes less —
            // he is buying a chance at the ending he wants, and both sides know
            // there are not many autumns left to spend. On a club going nowhere
            // the same man charges for his time instead.
            //
            // Gated on `weeksPlayed >= 6` for the same reason the two lines
            // above it are: this is a reaction to a season, and a neutral
            // situation (which is what the AI free-agent market prices against)
            // must stay exactly neutral. Verified against the existing
            // motivation term, which discounts a `.winning` man −0.12 on a
            // contender: the two stack, and both now REACH the ask, because the
            // opening band's floor is 0.75× market rather than the 1.0× that
            // used to quietly delete every discount this model computed.
            if isLegacyVeteran(player) {
                team += situation.isContender ? -legacyVeteranDiscount : 0.04
            }
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
    /// Three sources, in order of precedence.
    ///
    /// 1. **The ring-chaser**, checked first because it is the only never-sign
    ///    stance and its exit condition is the narrowest: if a man who cannot be
    ///    bought at any price were allowed to draw `.losingCulture` instead, the
    ///    chat would promise him back next league year and then not deliver.
    /// 2. The shared stance model (`AgentRefusalReason.evaluate`) — benched,
    ///    wants out, riding into retirement, losing culture — deliberately the
    ///    chat layer's vocabulary so the badge, the opening line and this verdict
    ///    cannot disagree.
    /// 3. One economy-owned addition the stance model has no inputs for: **a
    ///    mercenary will not sign up to lose for a front office he does not
    ///    rate.** That door opens wider the worse the GM's standing is, which is
    ///    the "bad GM gets more refusals" half of the brief.
    ///
    /// Door 3's threshold came down from 18 % to 8 % and gained a morale gate in
    /// this wave, for the budget reason documented on `AgentRefusalReason.evaluate`:
    /// a quarter of the league is money-motivated or a lone wolf, and on a bad
    /// team nearly one in five of them was refusing to take the call. It is a
    /// stance for a man who is visibly unhappy about losing, not for everybody
    /// who happens to like being paid.
    static func refusalVerdict(
        player: Player,
        situation: NegotiationSituation,
        gm: GMAdjustment
    ) -> AgentRefusalReason? {
        if ringChaserVerdict(player: player, situation: situation) {
            return .ringChasing
        }

        if let stance = AgentRefusalReason.evaluate(
            playerID: player.id,
            season: situation.season,
            age: player.age,
            overall: player.overall,
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
              player.morale < 65,
              situation.weeksPlayed >= 6,
              situation.teamWinPercentage < 0.35
        else { return nil }

        // 8 % at a neutral front office, rising toward 23 % at the worst one the
        // GM factor can produce. Deterministic, on a salt no other agent trait
        // uses, so the answer does not change between two openings of the same
        // conversation — but salted by the season as well, so a door that closed
        // one league year is not closed for the rest of his career.
        let threshold = 0.08 + Swift.max(0, gm.total) * 1.0
        let salt = 0xA7 ^ (UInt64(bitPattern: Int64(situation.season)) &* 0x9E37_79B9_7F4A_7C15)
        return unitDraw(player.id, salt: salt) < threshold ? .losingCulture : nil
    }

    // MARK: - The Loser Tax (D4-C / F-59)

    /// **Whether a free agent will take the call from a club that loses.**
    ///
    /// The extension-side refusal model has had a `.losingCulture` stance since
    /// it shipped, and it was structurally unreachable for a stranger:
    /// `demand` gated the whole verdict on `negotiationType.isOwnClub`. So the
    /// game shipped a losing-culture mechanic that could only ever fire on a
    /// club's own players, i.e. on the men who had already chosen to be there.
    /// D4-C is the other half — the fast rebuild has no downside today, and this
    /// is one of the two places to put one.
    ///
    /// ## The gates, and why each one
    ///
    /// * **The record has to exist.** `weeksPlayed >= 8` — the same evidence bar
    ///   `AgentRefusalReason.evaluate` uses, so the two models cannot disagree
    ///   about when a record starts meaning something. In March this reads last
    ///   season's completed 18, which is exactly the season a free agent is
    ///   judging a club on.
    /// * **The club has to be genuinely bad.** `wins * 3 <= played` — again the
    ///   stance model's own definition, so "a losing club" is one thing in this
    ///   file.
    /// * **He has to have a choice.** ``losingCultureFloorOverall``: a fringe
    ///   player takes the job that is offered. Only a man the market wants can
    ///   afford an opinion, which is also what keeps this from thinning the
    ///   bottom of the market, where the AI refill and the practice squad live.
    ///
    /// ## The magnitude
    ///
    /// ``losingCultureRefusalChance`` at 0.18, drawn deterministically on the
    /// player. On a 3-14 club roughly one good free agent in six will not
    /// engage; the other five will, at a price the loser tax (D1) sets. That is
    /// a real cost with a visible cause, and it is deliberately not large enough
    /// to make a rebuild unplayable: the men who say no are named, and there is
    /// always somebody who says yes.
    ///
    /// ## The salt is `yearsPro`, not the season, and that is load-bearing
    ///
    /// A stance verdict that is a pure function of a fixed UUID never changes,
    /// so a man who once drew "won't sign for a loser" would refuse for the rest
    /// of his career — the failure `refusalVerdict` salts the season against.
    /// The season is not reachable from every surface that has to ask this
    /// question, though: the bid-resolution path in `FreeAgencyEngine` carries
    /// bids and a roster and no league year, and threading one through it would
    /// mean a new parameter on a call chain the lead is rewriting this wave.
    /// `player.yearsPro` ticks exactly once per league year at the rollover, so
    /// it is the same clock with none of the plumbing — and because BOTH entry
    /// points salt on it, the negotiation screen and the bid resolver can never
    /// give the same man two different answers about the same club.
    ///
    /// **Neutral by construction.** `NegotiationSituation.neutral` carries
    /// `weeksPlayed == 0`, and `FreeAgencyEngine.agentDemand` — the pricing call
    /// behind `projectedAskingPrice`, the tampering rumour mill and the whole
    /// bulk market — passes exactly that. So this changes no price anywhere; it
    /// only answers a suitor who has said who he is.
    static func freeAgentRefusalVerdict(
        player: Player,
        situation: NegotiationSituation
    ) -> AgentRefusalReason? {
        guard situation.weeksPlayed >= 8 else { return nil }
        guard refusesLosingSuitor(
            player: player,
            record: (wins: situation.teamWins, losses: situation.teamLosses)
        ) else { return nil }
        return .losingCulture
    }

    /// The same verdict as a plain yes/no, for the surfaces that hold a club's
    /// record but no `NegotiationSituation` — `FreeAgencyEngine`'s bid
    /// resolution, where a refused club's offer simply is not on the table.
    ///
    /// - Parameter record: the suitor's season. `nil` means "no record on file",
    ///   which is never a refusal — a club nobody can evaluate gets the benefit
    ///   of the doubt.
    static func refusesLosingSuitor(
        player: Player,
        record: (wins: Int, losses: Int)?
    ) -> Bool {
        guard let record else { return false }
        let played = record.wins + record.losses
        guard played >= 8, record.wins * 3 <= played else { return false }
        guard player.overall >= losingCultureFloorOverall else { return false }

        let salt = 0x5C ^ (UInt64(player.yearsPro) &* 0x9E37_79B9_7F4A_7C15)
        return unitDraw(player.id, salt: salt) < losingCultureRefusalChance
    }

    /// Rating below which a free agent takes whatever job is offered.
    static let losingCultureFloorOverall = 78

    /// Chance a free agent good enough to choose refuses a losing club outright.
    static let losingCultureRefusalChance = 0.18

    // MARK: - The Ring-Chaser (never-sign)

    /// **The rarest stance in the game, and the only one money cannot touch.**
    ///
    /// An elite defender in his prime on a club that loses does not want a
    /// bigger contract — he wants January. The gates below exist to keep that
    /// story at the frequency it earns its weight at: the user's own roster
    /// should produce roughly one of these every couple of seasons, and the
    /// league one to three per year.
    ///
    /// Every gate is **structural** — a fact about the man or the standings, not
    /// a die roll — because a probability alone scales with roster size and
    /// would drift as a league grows. The single draw at the end is the tiebreak
    /// among the handful who clear everything else, and it is deliberately NOT
    /// salted by the season: a stance whose stated exit condition is "become a
    /// contender" must not quietly evaporate in a league year where the club is
    /// just as bad. It persists until the record changes, which is what makes
    /// the exit condition true.
    ///
    /// ## Why it lands where it does
    ///
    /// Multiplying the gates through a typical league: ~2.5 % of players are
    /// 88+; roughly 40 % of clubs are under .450 by week six; ~28 % of players
    /// are `.winning`-motivated or fiery competitors; the 80-competitiveness
    /// floor keeps about half of those; morale under 75 about half again; and
    /// the draw halves it once more. That is on the order of **one or two men
    /// league-wide per season**, before the extension window narrows it further
    /// (nobody negotiates an extension with a man who has four years left).
    /// `stanceCensus` measures the real number rather than trusting this
    /// arithmetic.
    static func ringChaserVerdict(player: Player, situation: NegotiationSituation) -> Bool {
        guard player.overall >= ringChaserOverallGate else { return false }
        // A 23-year-old star still believes he is going to fix the place. This
        // is a stance for a man far enough in to know better.
        guard player.age >= 26 else { return false }
        guard player.competitiveness >= ringChaserCompetitivenessGate else { return false }
        guard player.personality.motivation == .winning
                || player.personality.archetype == .fieryCompetitor
        else { return false }
        // A man who is happy is not demanding out, however bad the record.
        guard player.morale < 75 else { return false }
        guard isGoingNowhere(wins: situation.teamWins, losses: situation.teamLosses) else {
            return false
        }
        // Salt 0xD5 — used by nothing else, so the ring-chaser draw does not
        // correlate with the persona, the theatre or the mercenary door.
        return unitDraw(player.id, salt: 0xD5) < ringChaserDraw
    }

    // MARK: - The Legacy Veteran

    /// The Brady clause: an aging great who is still genuinely elite.
    ///
    /// Two effects, in two places, and both are the same idea seen from either
    /// side of a signature — he discounts for a contender
    /// (`situationBreakdown`'s team term) and, as a free agent, walks away from
    /// a loser for less money elsewhere
    /// (`FreeAgencyEngine.legacyVeteranPreference`).
    static func isLegacyVeteran(_ player: Player) -> Bool {
        player.age >= legacyVeteranAgeGate && player.overall >= legacyVeteranOverallGate
    }

    // MARK: - Stance

    /// Names the story the numbers are telling, for the chat to say out loud.
    private static func stance(
        player: Player,
        situation: NegotiationSituation,
        refusal: AgentRefusalReason?,
        isProveIt: Bool
    ) -> NegotiationStance? {
        if refusal == .ringChasing { return .ringChaser }
        if situation.provedTheBet { return .provenBet }
        if isLegacyVeteran(player) { return .legacyVeteran }
        if isProveIt { return .proveIt }
        return nil
    }

    // MARK: - Structure Preferences

    /// Opening frame for an agent who IS willing to talk.
    ///
    /// The proven bet overrides the persona, and it is the only thing that does:
    /// a man who took one year to rebuild his market and then delivered opens
    /// every conversation from the same place regardless of who represents him,
    /// because he is the one holding the evidence this time.
    private static func openingTone(
        persona: AgentPersona,
        player: Player,
        situation: NegotiationSituation
    ) -> AgentToneKey {
        if situation.provedTheBet { return .hardline }
        switch persona {
        case .hardliner:   return .hardline
        case .cooperative: return player.morale >= 75 ? .eager : .professional
        case .loyalist:    return player.loyaltyYears >= 3 ? .eager : .professional
        }
    }

    /// A prove-it deal is a bet, not a concession: a man whose market has just
    /// been marked down takes one year, plays well, and comes back at a price
    /// this contract could not have got him.
    ///
    /// The `provedTheBet` guard is what closes the loop. Without it a player who
    /// had just WON a prove-it bet still read as a prove-it candidate the
    /// following winter — a short cheap deal every year forever, which is the
    /// exact opposite of the mechanic. Once the bet lands he is done betting.
    private static func wantsProveItDeal(player: Player, situation: NegotiationSituation) -> Bool {
        guard !situation.provedTheBet else { return false }
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
        salaryCap: Int,
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
        let outcome: AgentNegotiationOutcome
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
        /// The offer was tabled at a client who had already declined to
        /// negotiate. Not a grade on the money — the money was never read.
        var isPestering: Bool = false
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
        // **Pestering.** A client who will not talk cannot be negotiated into
        // talking — but the club is entitled to keep trying, and the model has
        // to price that rather than forbid it.
        //
        // What used to happen here was `.playerWalked`, which ended the thread:
        // one offer to an unwilling man and the conversation was over for the
        // league year, with no way back and nothing learned. That is a rule the
        // league does not have. A front office CAN table another offer; what it
        // cannot do is make the offer be the answer.
        //
        // So the money is not graded at all — it was never the question — and
        // the offer costs exactly what ignoring somebody costs: the standing ask
        // ratchets (`escalated()`, the same 6 % a lowball buys), a round of
        // patience is gone with it, the ledger books it as an insult because
        // that is what the agent community would call it, and the chat layer
        // takes `pesterMoraleCost` off the man himself. The outcome stays
        // `.pending` so the composer survives; the tone stays `.refusing` so
        // every downstream surface still knows the door is shut.
        guard !demand.isRefusing else {
            if recordToLedger { NegotiationLedger.recordInsult() }
            let escalated = demand.escalated()
            return AgentResponse(
                tone: .refusing, counterOffer: nil, outcome: .pending,
                demand: escalated, isYearsPushback: false,
                counterPerYear: escalated.askAmount,
                isPestering: true
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
        //
        // The prove-it client counts them for MORE. That is the whole shape of
        // the Mayfield deal: a man whose market has just been marked down is not
        // arguing about guaranteed money, he is buying a stage — so clause money
        // he has to earn is money he was betting on anyway, and a short term is
        // part of what he came for rather than a concession the club has to buy
        // back. Both credits are applied here, in the grading, so they change
        // what an offer is WORTH to him without touching the ask or the floor —
        // which is what keeps the AI free-agent market (which never writes
        // clauses and never calls this) bit-identical.
        let years = max(1, gmOffer.years)
        let rawCredit = ContractEngine.creditedIncentiveValue(
            gmOffer.incentives, player: player, persona: persona, years: years
        ) / years
        let creditedPerYear = demand.isProveIt
            ? Int(Double(rawCredit) * proveItIncentiveCredit)
            : rawCredit
        let shortDealCredit = demand.isProveIt && gmOffer.years <= 2
            ? proveItShortDealCredit
            : 1.0

        // Guarantees are the other half of an offer. A number that matches the
        // ask on paper but guarantees 20 points less of it is not the same
        // offer, and an agent prices that gap rather than ignoring it.
        let guaranteeGap = previousAgentOffer.guaranteedPercent - gmOffer.guaranteedPercent
        let guaranteeDrag = guaranteeGap > 15 ? 0.96 : 1.0

        let effectivePerYear = Int(
            Double(gmOffer.annualCapHit + creditedPerYear) * guaranteeDrag * shortDealCredit
        )
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

    // MARK: - Pay Cut (cap-compliance lever)

    /// The veteran minimum, in thousands — the floor no negotiated salary may go
    /// under.
    ///
    /// A one-line forward to ``ContractEngine/veteranMinimum(cap:)``, which is
    /// the harness-anchored definition. It exists at all because
    /// ``demand(player:negotiationType:salaryCap:situation:standing:insultCount:)``
    /// had the constant inline as a local `minimum`, and the pay-cut model needs
    /// the same floor by name. Two literals for "the least a man can be paid" is
    /// precisely the class of split the #87 wave existed to end.
    static func veteranMinimum(salaryCap: Int) -> Int {
        ContractEngine.veteranMinimum(cap: salaryCap)
    }

    /// What a pay-cut ask is answered with.
    ///
    /// Deliberately NOT ``AgentNegotiationOutcome``: a pay cut is a yes/no question
    /// about one number, not a bid/counter loop that can walk away or break off
    /// for the offseason. Reusing the four-way outcome would have made every
    /// downstream `switch` claim to handle states this conversation cannot enter.
    enum PayCutOutcome: Equatable {
        /// He signs the reduction as asked.
        case accepted
        /// He will go down, but only to `perYear` — the club's ask went past his
        /// floor and he says where the floor is.
        case countered(perYear: Int)
        /// No. The deal is the deal.
        case refused
        /// "If you can't pay him, release him." A star asked to fund the club's
        /// mistake would rather test the market — the answer the design brief
        /// names for exactly this case.
        case demandsRelease
    }

    /// **The pay-cut consent model.** One graded ask, in the shape the chat needs.
    ///
    /// The shape of the answer, and why:
    ///
    /// | who | what happens |
    /// |---|---|
    /// | veteran carrying an ABOVE-market deal | accepts down to roughly his real market, with a morale cost |
    /// | anyone asked to go BELOW his market | counters at his floor rather than refusing outright |
    /// | 85+ OVR whose deal is at or under market | refuses — he is not the club's cap problem |
    /// | 85+ OVR pushed more than a third under market | demands his release |
    ///
    /// **Leverage is the whole model.** A cut is only signable when the player
    /// could not get the same money elsewhere, so the pivot is
    /// `proposedSalary` against ``ContractDemand/marketValue`` — never against
    /// what he is currently paid. A man on $18M whose market is $6M has no
    /// leverage and every agent knows it; a man on $18M whose market is $20M is
    /// being asked to donate, and no agent signs that.
    ///
    /// Persona moves the floor, it does not decide the answer: a loyalist will
    /// go a little under his market for a club that has treated him well, a
    /// hardliner will not go a cent under it, and a deal-maker sits between.
    ///
    /// Nothing here is a roll. The same ask gets the same answer every time it
    /// is made, which is what lets the workspace preview a lever and the chat
    /// deliver it without the two disagreeing.
    struct PayCutVerdict {
        let outcome: PayCutOutcome
        /// The frame the answer is spoken in — what the bubble and the chip key
        /// off, same as every other agent line.
        let tone: AgentToneKey
        /// Morale the player loses if the club goes through with the ask. Signed
        /// (always ≤ 0). A cut he consents to still stings; one he refused and
        /// the club never applied costs nothing, which is why the caller applies
        /// this only on ``PayCutOutcome/accepted``.
        let moraleDelta: Int
        /// The lowest per-year number he would sign, in thousands. The counter
        /// when there is one, and the honest answer to "how far can I push this"
        /// for every other outcome.
        let concessionFloor: Int
        /// The unadjusted market for the man — what the floor is measured from.
        let marketValue: Int
        /// This year's cap relief the club books if he signs, in thousands.
        let savings: Int

        var isAccepted: Bool { outcome == .accepted }
    }

    /// Grade one pay-cut ask.
    ///
    /// - Parameters:
    ///   - demand: the SAME demand the extension conversation would use — this
    ///     is a `.payCut` type, so `isOwnClub` is on and the refusal gate has
    ///     already run. A refusing client answers every pay-cut ask with
    ///     `.refused`, whatever the number: a man who will not talk about more
    ///     money is certainly not discussing less.
    ///   - currentSalary: what the club is charged for him today, in thousands.
    ///   - proposedSalary: the club's ask, in thousands.
    static func payCutVerdict(
        player: Player,
        demand: ContractDemand,
        currentSalary: Int,
        proposedSalary: Int,
        salaryCap: Int
    ) -> PayCutVerdict {

        let market = max(1, demand.marketValue)
        let minimum = veteranMinimum(salaryCap: salaryCap)
        let current = max(0, currentSalary)
        let proposed = max(minimum, proposedSalary)
        let savings = max(0, current - proposed)

        // How far under his own market this agent will go for this club. A
        // loyalist has a relationship to spend; a hardliner has none to spend.
        let personaGive: Double = {
            switch demand.persona {
            case .hardliner:   return 0.00
            case .cooperative: return 0.06
            case .loyalist:    return 0.12
            }
        }()

        // Morale is the other half of leverage: a man who likes it here signs a
        // number a man who is already unhappy would not.
        let moraleGive: Double = {
            switch player.morale {
            case ..<40:   return -0.06
            case 40..<55: return -0.03
            case 55..<70: return 0.0
            case 70..<85: return 0.03
            default:      return 0.06
            }
        }()

        // An aging player with a short deal left has fewer places to go. This is
        // small on purpose — it is a nudge, not a second market model.
        let ageGive = player.age >= 32 ? 0.04 : (player.age <= 25 ? -0.03 : 0.0)

        let give = max(0.0, personaGive + moraleGive + ageGive)
        let floor = max(minimum, Int(Double(market) * (1.0 - give)))

        // A client who is not at the table is not at this table either.
        guard !demand.isRefusing else {
            return PayCutVerdict(
                outcome: .refused, tone: .refusing, moraleDelta: 0,
                concessionFloor: floor, marketValue: market, savings: 0
            )
        }

        // A star whose contract is not the problem. `starGate` is the tier where
        // a man can credibly say "release me and watch who signs me by Friday"
        // — and mean it.
        let isStar = player.overall >= payCutStarGate
        let isAboveMarket = current > Int(Double(market) * 1.05)

        if isStar && !isAboveMarket {
            // Pushed hard enough and he stops arguing about the number.
            if proposed < Int(Double(market) * payCutReleaseDemandRatio) {
                return PayCutVerdict(
                    outcome: .demandsRelease, tone: .insulted,
                    moraleDelta: payCutReleaseDemandMoraleCost,
                    concessionFloor: floor, marketValue: market, savings: 0
                )
            }
            return PayCutVerdict(
                outcome: .refused, tone: .hardline, moraleDelta: 0,
                concessionFloor: floor, marketValue: market, savings: 0
            )
        }

        // Asking for MORE than he is on is not a pay cut; the composer should
        // never send it, and if it does it is simply declined.
        guard proposed < current else {
            return PayCutVerdict(
                outcome: .refused, tone: .professional, moraleDelta: 0,
                concessionFloor: floor, marketValue: market, savings: 0
            )
        }

        if proposed >= floor {
            // He signs. What it costs him is how far under his market he has
            // been talked, scaled so a token trim is nearly free and a walk all
            // the way to the floor is felt.
            let depth = Double(market - proposed) / Double(market)
            let scaled = Int((max(0.0, depth) * payCutMoraleSpan).rounded())
            let delta = -min(payCutMaxMoraleCost, payCutBaseMoraleCost + scaled)
            return PayCutVerdict(
                outcome: .accepted,
                tone: proposed >= market ? .professional : .hardline,
                moraleDelta: delta,
                concessionFloor: floor, marketValue: market, savings: savings
            )
        }

        // Below his floor but still a real conversation: he names his number.
        // A hardliner's counter is his market to the cent, which is what makes
        // "who represents him" worth knowing before the call.
        //
        // UNLESS his floor is already at or above what the club pays him — a man
        // on a below-market deal has nothing to give back, and `min(current,
        // floor)` would have him "counter" at the exact salary he is on. The
        // chat renders that as "He'll go to $12.0M. That is his floor — set the
        // dial there and ask again", and at that number the Ask button is
        // disabled because it saves nothing: a loop with no exit and no
        // explanation. The honest answer is the one the money already gives.
        guard floor < current else {
            return PayCutVerdict(
                outcome: .refused, tone: .professional, moraleDelta: 0,
                concessionFloor: floor, marketValue: market, savings: 0
            )
        }

        let counter = min(current, floor)
        return PayCutVerdict(
            outcome: .countered(perYear: counter),
            tone: proposed < Int(Double(floor) * insultRatio) ? .insulted : .professional,
            moraleDelta: 0,
            concessionFloor: counter, marketValue: market,
            savings: max(0, current - counter)
        )
    }

    // MARK: Pay-cut tuning

    /// OVR at which a man can answer a pay-cut ask with "then release me" and be
    /// right. Deliberately below ``ringChaserOverallGate`` (88): refusing to
    /// fund the club's cap mistake takes far less standing than refusing to play
    /// for it at all.
    static let payCutStarGate = 85

    /// How far under his market a star has to be pushed before the answer stops
    /// being "no" and becomes "release me". Two thirds of market is the point
    /// where the club is no longer negotiating, it is asking for a donation.
    static let payCutReleaseDemandRatio = 0.67

    /// The relationship cost of asking a star to fund the club's cap problem.
    /// Charged whether or not the club follows through — the ask is the insult.
    static let payCutReleaseDemandMoraleCost = -12

    /// Morale a consented cut costs before depth is priced in.
    static let payCutBaseMoraleCost = 2

    /// Morale points spread across "cut to market" → "cut to the floor".
    static let payCutMoraleSpan = 40.0

    /// Ceiling on the morale cost of a cut the man agreed to. A pay cut is a bad
    /// day, not a trade request — the club that keeps him has to be able to keep
    /// coaching him.
    static let payCutMaxMoraleCost = 10

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
        let outcome: AgentNegotiationOutcome
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
        /// The offer went to a client who had already declined to negotiate.
        /// The caller owes the man `pesterMoraleCost` morale and owes the
        /// transcript an escalating line from `AgentDialogue.pesteringLine`.
        var isPestering: Bool = false
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
        salaryCap: Int,
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
                isYearsPushback: response.isYearsPushback,
                isPestering: response.isPestering
            )
        }

        // Pestering short-circuits the outcome switch: the offer was never
        // graded, so there is no counter to describe and no walk to explain.
        // The caller supplies the wording (it owns the agent's voice); this is
        // the fallback for surfaces that do not.
        if response.isPestering {
            return verdict(
                "I've told you — this isn't about the number. My client isn't interested."
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
        case .payCut:
            // A pay-cut call never opens with an ask — the CLUB is asking. This
            // is the agent picking up, knowing why the phone rang.
            let messages = [
                "I know why you're calling. Before you say the number: \(name) signed that deal in good faith, and he's played to it.",
                "Cap trouble is the club's problem, not \(name)'s. But I'll listen — tell me what you need.",
                "We can have this conversation. It has to be worth having, though — \(name) isn't giving money back for nothing."
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

    // MARK: - Stance Census (rarity budget instrumentation)

    /// How many men in a league are actually eligible for each stance.
    ///
    /// **The budget is a claim, and a claim needs a measurement.** Every gate in
    /// this file was tuned against arithmetic — "88+ is about 2.5 % of a
    /// calibrated league" — and arithmetic drifts as a league ages, as ratings
    /// inflate, as the generator changes. This counts the real thing on a real
    /// roster set, so the claim can be checked rather than believed.
    ///
    /// Eligibility, not incidence: a refusal only actually happens when somebody
    /// picks up the phone, so `refusals` here is the size of the population that
    /// WOULD refuse if contacted — the conservative reading, and the one the
    /// `< 5 %` budget is written against.
    struct StanceCensus {
        var players = 0
        var refusals = 0
        var ringChasers = 0
        var legacyVeterans = 0
        var proveIts = 0
        /// Refusing share of the population, as a percentage.
        var refusalPercent: Double {
            players == 0 ? 0 : Double(refusals) / Double(players) * 100
        }
        var summary: String {
            String(
                format: "n=%d refusing=%d (%.1f%%, budget <5%%) ringChasers=%d legacyVets=%d proveIt=%d",
                players, refusals, refusalPercent, ringChasers, legacyVeterans, proveIts
            )
        }
    }

    /// Runs every stance gate over a roster set. `recordByTeamID` supplies the
    /// standings the situation-driven stances read; a player whose club is
    /// missing from it is measured against a neutral season, which is the
    /// conservative direction (no ring-chasers, no losing-culture refusals).
    static func stanceCensus(
        players: [Player],
        recordByTeamID: [UUID: (wins: Int, losses: Int)],
        season: Int,
        weeksPlayed: Int
    ) -> StanceCensus {
        var census = StanceCensus()
        for player in players where !player.isRetired {
            census.players += 1
            let record = player.teamID.flatMap { recordByTeamID[$0] } ?? (wins: 0, losses: 0)
            let situation = situation(
                for: player,
                season: season,
                teamWins: record.wins,
                teamLosses: record.losses,
                weeksPlayed: weeksPlayed
            )
            if let reason = refusalVerdict(
                player: player, situation: situation, gm: .neutral
            ) {
                census.refusals += 1
                if reason == .ringChasing { census.ringChasers += 1 }
            }
            if isLegacyVeteran(player) { census.legacyVeterans += 1 }
            if wantsProveItDeal(player: player, situation: situation) { census.proveIts += 1 }
        }
        return census
    }
}

// MARK: - Prove-It Registry

/// Which players took a short deal to bet on themselves, and in which league
/// year.
///
/// **Why this has to be persisted.** Everything else the demand model reads is a
/// property of the player row — age, rating, morale, snaps. "He signed a
/// one-year prove-it deal last winter" is not: it is a fact about a *contract
/// this save wrote*, and by the time it matters the deal it describes is either
/// expiring or expired. Without a record of it the bounce-back half of the
/// mechanic is unreachable, and a prove-it deal becomes a permanent discount the
/// club renews every year — which is the exact opposite of a bet.
///
/// careerID-scoped `UserDefaults`, the `NegotiationLockRegistry` /
/// `ContractIncentiveRegistry` shape: a handful of entries per save, written a
/// few times an offseason, and listed in `CareerScopedDefaults.keys` so a
/// deleted career takes its bets with it. No SwiftData migration.
enum ProveItRegistry {

    /// Base key — namespaced per save through `CareerScopedDefaults.scopedKey`.
    /// Never read bare (see `NegotiationLockRegistry.baseKey`).
    static let defaultsKey = "proveItDealSeasons"

    private static var key: String { CareerScopedDefaults.scopedKey(defaultsKey) }

    /// The league year this player signed a prove-it deal in, if he did.
    static func betSeason(_ playerID: UUID) -> Int? {
        table()[playerID.uuidString]
    }

    /// Books a signed prove-it deal. Overwrites: a man can bet on himself more
    /// than once in a career, and only the most recent bet is the live one.
    static func record(playerID: UUID, season: Int) {
        var t = table()
        t[playerID.uuidString] = season
        write(t)
    }

    /// Settles a bet — called once its premium has been charged, so a single
    /// bounce-back season cannot be sold twice.
    static func clear(playerID: UUID) {
        var t = table()
        t.removeValue(forKey: playerID.uuidString)
        write(t)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func table() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func write(_ t: [String: Int]) {
        UserDefaults.standard.set(t, forKey: key)
    }
}

// MARK: - Trade Request Registry

/// Players who have publicly asked out, and the league year they asked in.
///
/// **A request is not a trade.** It is two things and deliberately no more: a
/// news story the league reacts to, and a flag the trade AI can read
/// (`TradeValueEngine.saleCandidates` treats a requesting player as available
/// regardless of the selling club's stance, which is what a real front office
/// does the morning after a star's agent goes public). No new trade mechanics,
/// no forced execution — `HoldoutEngine.forceTrade` already owns the "he is
/// actually leaving" path, and a request that shipped the man out on its own
/// would take the decision away from the user, who is the one being asked.
///
/// Same storage shape and lifetime as `ProveItRegistry`.
enum TradeRequestRegistry {

    static let defaultsKey = "tradeRequestSeasons"

    private static var key: String { CareerScopedDefaults.scopedKey(defaultsKey) }

    /// The league year he asked out in, if he has.
    static func requestSeason(_ playerID: UUID) -> Int? {
        table()[playerID.uuidString]
    }

    /// Whether a request is standing right now. Season-checked rather than a
    /// bare flag: a demand made three years ago on a team that has since won a
    /// division is not a demand, it is history.
    ///
    /// `season: nil` means the caller genuinely does not know the league year
    /// (some of the trade market's private helpers do not carry one), and it
    /// falls back to "any recorded request counts". That is the conservative
    /// direction for THIS flag — it can only ever make a man more available,
    /// never less, and being available is what he asked for.
    static func hasStandingRequest(_ playerID: UUID, season: Int?) -> Bool {
        guard let asked = table()[playerID.uuidString] else { return false }
        guard let season else { return true }
        return asked >= season - 1
    }

    /// Records a request. Returns `false` when one was already standing, so the
    /// caller can avoid writing the same news story twice.
    @discardableResult
    static func record(playerID: UUID, season: Int) -> Bool {
        var t = table()
        if let existing = t[playerID.uuidString], existing >= season { return false }
        t[playerID.uuidString] = season
        write(t)
        return true
    }

    /// Withdraws a request — he was traded, or the club won him back.
    static func clear(playerID: UUID) {
        var t = table()
        t.removeValue(forKey: playerID.uuidString)
        write(t)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func table() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private static func write(_ t: [String: Int]) {
        UserDefaults.standard.set(t, forKey: key)
    }
}

// MARK: - Pay Cut Registry (cap-compliance wave, #102 F9)

/// Which men have already answered the pay-cut question this league year, and
/// which of those answers has already been paid for.
///
/// **The hole this closes.** `ContractNegotiationView.payCutSettled` is `@State`
/// and a pay-cut talk deliberately never reaches `NegotiationThreadStore` (one
/// thread per player per save, no room for the type — writing one would clobber
/// the club's live extension transcript). Between them that meant the latch died
/// with the sheet: dismiss, reopen, and the composer was live again on a man who
/// had already taken his cut, while `demandsRelease` re-applied its −12 morale
/// on every single reopen. A conversation you can restart until you like the
/// answer is not a conversation, and a morale charge you can farm by tapping
/// Close is a bug the user is rewarded for finding.
///
/// Two tables, both `[playerID: seasonYear]`, both careerID-scoped
/// `UserDefaults` in the `ProveItRegistry` / `TradeRequestRegistry` shape and
/// both listed in `CareerScopedDefaults.keys`. Season-stamped rather than a bare
/// flag because the question genuinely reopens in March: a new league year is a
/// new set of books and a new conversation.
enum PayCutRegistry {

    /// He signed a reduced deal — the composer stays closed for the rest of the
    /// league year.
    static let settledKey = "payCutSettledSeasons"

    /// His camp answered "then release me" and the club has already been
    /// charged the morale for asking.
    static let releaseDemandKey = "payCutReleaseDemandSeasons"

    // MARK: - Settled

    static func isSettled(playerID: UUID, season: Int) -> Bool {
        table(settledKey)[playerID.uuidString] == season
    }

    static func recordSettled(playerID: UUID, season: Int) {
        var t = table(settledKey)
        t[playerID.uuidString] = season
        write(t, settledKey)
    }

    // MARK: - Release demand

    /// Books the release-demand morale charge, once per man per league year.
    /// Returns `false` when this season's charge has already been applied, so
    /// the caller can skip the morale write rather than re-apply it.
    @discardableResult
    static func chargeReleaseDemand(playerID: UUID, season: Int) -> Bool {
        var t = table(releaseDemandKey)
        guard t[playerID.uuidString] != season else { return false }
        t[playerID.uuidString] = season
        write(t, releaseDemandKey)
        return true
    }

    // MARK: - Lifecycle

    /// Forgets a man entirely — he was released, retired or traded away, and a
    /// new club has to be able to ask him the question itself.
    static func clear(playerID: UUID) {
        for base in [settledKey, releaseDemandKey] {
            var t = table(base)
            guard t.removeValue(forKey: playerID.uuidString) != nil else { continue }
            write(t, base)
        }
    }

    static func reset() {
        for base in [settledKey, releaseDemandKey] {
            UserDefaults.standard.removeObject(forKey: CareerScopedDefaults.scopedKey(base))
        }
    }

    private static func table(_ base: String) -> [String: Int] {
        UserDefaults.standard
            .dictionary(forKey: CareerScopedDefaults.scopedKey(base)) as? [String: Int] ?? [:]
    }

    private static func write(_ t: [String: Int], _ base: String) {
        UserDefaults.standard.set(t, forKey: CareerScopedDefaults.scopedKey(base))
    }
}
