import Foundation

/// Evaluates draft trade offers using the Jimmy Johnson chart with need bonus,
/// future-pick discount, and GM-personality factor.
///
/// Vaihe 3 piece. Used by:
/// - Trade Builder UI when the user proposes terms (`evaluate`)
/// - Coordinator/AI loop deciding whether an AI partner should *initiate* a
///   trade-up at the user's pick (`aiInitiatedOfferConsidered`)
enum TradeEvaluator {

    // MARK: - Personality

    /// Each AI GM has a personality archetype that biases their trade
    /// behaviour. Personality nudges the verdict thresholds and the chance of
    /// initiating an offer.
    enum GMPersonality {
        case aggressive   // chases stars, will pay a premium to move up
        case balanced     // neutral, sticks close to chart value
        case patient      // values future picks, prefers to move down
        case opportunist  // jumps when value mismatches show up

        /// Threshold (in JJ points) where the AI swings from `decline` to
        /// `counter`. Anything more negative than this is auto-decline.
        fileprivate var declineThreshold: Int {
            switch self {
            case .aggressive:  return -80   // tolerates losing value to move up
            case .balanced:    return -50
            case .patient:     return -40
            case .opportunist: return -60
            }
        }

        /// Threshold where the AI flips from `counter` to `accept`.
        fileprivate var acceptThreshold: Int {
            switch self {
            case .aggressive:  return 40    // happy to overpay slightly
            case .balanced:    return 50
            case .patient:     return 60
            case .opportunist: return 30    // pounces on overpays
            }
        }

        /// Multiplier applied to the value of a pick if it lands in the
        /// partner's window of high need (encodes "I want this guy" willingness).
        fileprivate var needWeight: Double {
            switch self {
            case .aggressive:  return 0.25
            case .balanced:    return 0.15
            case .patient:     return 0.10
            case .opportunist: return 0.20
            }
        }

        /// Probability (0..1) of initiating a trade-up under the right
        /// circumstances each pick.
        fileprivate var initiateChance: Double {
            switch self {
            case .aggressive:  return 0.30
            case .balanced:    return 0.12
            case .patient:     return 0.05
            case .opportunist: return 0.18
            }
        }
    }

    // MARK: - Asset

    struct Asset: Hashable {
        let pickNumber: Int
        let seasonYear: Int        // current = curYear, future = curYear+N
        let isCurrentYear: Bool
    }

    // MARK: - Output

    struct OfferEvaluation {
        let outgoingValue: Int    // user gives away this many points
        let incomingValue: Int    // user receives this many points
        let delta: Int            // incomingValue - outgoingValue
        let aiVerdict: Verdict    // accept / counter / decline
        let reason: String        // user-visible motive
    }

    enum Verdict {
        case accept
        case counter(suggestedAdjustment: String)
        case decline(reason: String)
    }

    struct ProposedOffer {
        let partnerTeamID: UUID
        let partnerGives: [Asset]
        let partnerReceives: [Asset]
        let motive: String              // e.g. "Giants want a QB"
        let expirationSeconds: Int      // typically 90s
    }

    // MARK: - Constants

    /// Future-pick discount: a pick one year out is worth this fraction of
    /// the same slot in the current draft.
    static let futurePickDiscount: Double = 0.65

    // MARK: - Public API

    /// Evaluates an outgoing offer (user → AI). Used by Trade Builder when
    /// the user proposes terms.
    static func evaluate(
        userGives: [Asset],
        userReceives: [Asset],
        partnerNeeds: [Position: Double],
        targetPosition: Position?,
        gmPersonality: GMPersonality,
        currentYear: Int
    ) -> OfferEvaluation {
        // From the AI partner's perspective:
        //   "incoming"  = picks the partner *receives* = `userGives`
        //   "outgoing"  = picks the partner *sends*    = `userReceives`
        //
        // The chart delta is the partner's surplus; if positive they win the
        // exchange, if negative the user wins.
        let needFactor = needFactor(for: targetPosition, partnerNeeds: partnerNeeds, personality: gmPersonality)
        let partnerIncoming = valueOf(userGives, partnerNeedFactor: needFactor)
        let partnerOutgoing = valueOf(userReceives)

        let outgoingValueForUser = valueOf(userGives)
        let incomingValueForUser = valueOf(userReceives)
        let userFacingDelta = incomingValueForUser - outgoingValueForUser

        let partnerSurplus = partnerIncoming - partnerOutgoing

        let verdict: Verdict
        let reason: String
        if partnerSurplus < gmPersonality.declineThreshold {
            verdict = .decline(reason: "We can't justify giving up that much value.")
            reason = declineReason(targetPosition: targetPosition, gmPersonality: gmPersonality)
        } else if partnerSurplus >= gmPersonality.acceptThreshold {
            verdict = .accept
            reason = acceptReason(targetPosition: targetPosition, gmPersonality: gmPersonality)
        } else {
            // Counter: ask user to add ~|surplus_gap| points worth of capital
            let gap = max(20, gmPersonality.acceptThreshold - partnerSurplus)
            let suggestion = counterSuggestion(pointsNeeded: gap)
            verdict = .counter(suggestedAdjustment: suggestion)
            reason = counterReason(targetPosition: targetPosition, gmPersonality: gmPersonality)
        }

        return OfferEvaluation(
            outgoingValue: outgoingValueForUser,
            incomingValue: incomingValueForUser,
            delta: userFacingDelta,
            aiVerdict: verdict,
            reason: reason
        )
    }

    /// Computes weighted value of a list of assets. Future-year picks are
    /// discounted to 65% of their nominal chart value. An optional
    /// partnerNeedFactor multiplies the entire bundle to model the partner
    /// paying a premium for need-fitting picks (1.0 = neutral).
    static func valueOf(_ assets: [Asset], partnerNeedFactor: Double = 1.0) -> Int {
        let raw = assets.reduce(0.0) { acc, asset in
            let base = Double(PickValueChart.points(forPick: asset.pickNumber))
            let discount = asset.isCurrentYear ? 1.0 : futurePickDiscount
            return acc + base * discount
        }
        let weighted = raw * partnerNeedFactor
        return Int(weighted.rounded())
    }

    /// Decides whether the AI partner should INITIATE a trade up/down with
    /// the user at the current pick.
    ///
    /// Triggers when:
    ///   (a) Partner is on the clock 5+ slots above the user, AND
    ///   (b) A top-3 prospect at a position the partner needs is still on
    ///       the board, AND
    ///   (c) Random roll versus personality.initiateChance succeeds.
    ///
    /// Returns nil otherwise.
    static func aiInitiatedOfferConsidered(
        partnerTeamID: UUID,
        partnerNeeds: [Position: Double],
        partnerPersonality: GMPersonality,
        currentPick: Int,
        userPick: Int,
        boardTopProspects: [(prospectID: UUID, position: Position, rank: Int)]
    ) -> ProposedOffer? {
        // (a) Partner must be in front of the user with enough slack to be
        //     worth trading up.
        let slack = userPick - currentPick
        guard slack >= 5 else { return nil }

        // (b) A top-3-ranked prospect at a needed position must still be on
        //     the board for the partner to covet.
        let neededTop = boardTopProspects
            .filter { $0.rank <= 3 }
            .first(where: { (partnerNeeds[$0.position] ?? 0.0) >= 0.55 })
        guard let target = neededTop else { return nil }

        // (c) Personality-weighted random gate.
        let chance = partnerPersonality.initiateChance
        if Double.random(in: 0..<1) > chance { return nil }

        // Build the offer: partner trades down out of `currentPick`, gets
        // user's `userPick` plus a sweetener (a future Round-3 pick from the
        // user, encoded conventionally as round 3 in next year's draft).
        let partnerGives: [Asset] = [
            Asset(pickNumber: currentPick, seasonYear: 0, isCurrentYear: true)
        ]
        // Sweetener pickNumber heuristic: use round 3 slot equivalent of
        // userPick — the UI layer will resolve these into real future picks
        // as the user has them.
        let sweetenerPickNumber = min(96, userPick + 60)
        let partnerReceives: [Asset] = [
            Asset(pickNumber: userPick, seasonYear: 0, isCurrentYear: true),
            Asset(pickNumber: sweetenerPickNumber, seasonYear: 1, isCurrentYear: false)
        ]

        let positionLabel = target.position.rawValue
        let motive = "Partner targeting a \(positionLabel) at #\(userPick)"

        return ProposedOffer(
            partnerTeamID: partnerTeamID,
            partnerGives: partnerGives,
            partnerReceives: partnerReceives,
            motive: motive,
            expirationSeconds: 90
        )
    }

    // MARK: - Internal helpers

    private static func needFactor(
        for targetPosition: Position?,
        partnerNeeds: [Position: Double],
        personality: GMPersonality
    ) -> Double {
        guard let pos = targetPosition else { return 1.0 }
        let need = partnerNeeds[pos] ?? 0.0
        // Need is ~0..1; converts into a 1.0..(1.0 + needWeight) multiplier.
        return 1.0 + (need * personality.needWeight)
    }

    private static func counterSuggestion(pointsNeeded: Int) -> String {
        // Translate JJ points into approximate pick rounds for the user-facing
        // suggestion text.
        if pointsNeeded >= 600 {
            return "add a Round 1 pick"
        } else if pointsNeeded >= 300 {
            return "add a Round 2 pick"
        } else if pointsNeeded >= 130 {
            return "add a Round 3 pick"
        } else if pointsNeeded >= 60 {
            return "add a Round 4 pick"
        } else if pointsNeeded >= 25 {
            return "throw in a Day 3 pick"
        } else {
            return "sweeten with a late-round pick"
        }
    }

    private static func acceptReason(targetPosition: Position?, gmPersonality: GMPersonality) -> String {
        if let pos = targetPosition {
            return "We're locking in our \(pos.rawValue). Deal."
        }
        switch gmPersonality {
        case .aggressive:  return "Bold move — we like it. Deal."
        case .balanced:    return "Numbers work for both sides. Deal."
        case .patient:     return "Future capital is fine with us. Deal."
        case .opportunist: return "We'll take the value. Deal."
        }
    }

    private static func counterReason(targetPosition: Position?, gmPersonality: GMPersonality) -> String {
        if let pos = targetPosition {
            return "We see the \(pos.rawValue) angle, but we need a bit more."
        }
        switch gmPersonality {
        case .aggressive:  return "Close, but we need a sweetener."
        case .balanced:    return "Almost — the chart says you owe us a touch more."
        case .patient:     return "We can do this if you bump up the future capital."
        case .opportunist: return "Tweak the value and we'll talk."
        }
    }

    private static func declineReason(targetPosition: Position?, gmPersonality: GMPersonality) -> String {
        switch gmPersonality {
        case .aggressive:  return "Not enough star power coming back. Pass."
        case .balanced:    return "Chart's too lopsided. Pass."
        case .patient:     return "We'd rather keep our capital. Pass."
        case .opportunist: return "We don't see the value. Pass."
        }
    }
}
