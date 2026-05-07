import Foundation

/// Powers the Negotiation Room sheet (A7): user drags sliders for years / base /
/// signing-bonus / guarantees / incentives, and the agent surfaces verdicts plus
/// a counter-proposal when the offer falls short.
enum BiddingRoomEngine {

    // MARK: - Types

    /// Mutable draft offer composed by the user in the Negotiation Room sheet.
    /// All money values are in thousands.
    struct OfferDraft: Equatable, Hashable {
        var years: Int                // 1...7
        var baseSalary: Int           // thousands per year
        var signingBonus: Int         // thousands (lump sum)
        var guaranteed: Int           // thousands (total guaranteed)
        var incentives: Int           // thousands per year (avg)

        init(
            years: Int = 1,
            baseSalary: Int = 0,
            signingBonus: Int = 0,
            guaranteed: Int = 0,
            incentives: Int = 0
        ) {
            self.years = max(1, min(7, years))
            self.baseSalary = max(0, baseSalary)
            self.signingBonus = max(0, signingBonus)
            self.guaranteed = max(0, guaranteed)
            self.incentives = max(0, incentives)
        }

        /// Average annual value the team commits across the deal length.
        var annualValue: Int {
            guard years > 0 else { return baseSalary + signingBonus + incentives }
            return baseSalary + (signingBonus / max(years, 1)) + incentives
        }
    }

    /// Per-slider verdict shown back to the user.
    enum Verdict: String, Hashable {
        case tooLow
        case fair
        case great
    }

    /// Agent feedback bundle the UI renders after evaluating the draft.
    struct AgentFeedback: Equatable, Hashable {
        let yearsVerdict: Verdict
        let baseVerdict: Verdict
        let bonusVerdict: Verdict
        let guaranteeVerdict: Verdict
        let overallScore: Double          // 0.0 (terrible) ... 1.0 (great)
        let counterSuggestion: OfferDraft?
        let agentQuote: String
    }

    // MARK: - API

    /// Evaluates the user's draft offer through the agent's lens.
    /// - Parameters:
    ///   - draft: Current sliders.
    ///   - marketValue: Estimated annual fair-market value (thousands per year).
    ///   - playerLoyalty: 0.0 (mercenary) ... 1.0 (loyal). Loyal players accept lower offers.
    ///   - agentAggression: 0.0 (cooperative) ... 1.0 (cutthroat). Aggressive agents demand more.
    static func evaluateOffer(
        draft: OfferDraft,
        marketValue: Int,
        playerLoyalty: Double,
        agentAggression: Double
    ) -> AgentFeedback {
        let loyalty = clamp01(playerLoyalty)
        let aggression = clamp01(agentAggression)

        // Effective ask floor: aggressive agents push above market, loyal players accept below.
        let askMultiplier = 1.0 + (aggression - 0.5) * 0.40  // 0.80 ... 1.20
        let loyaltyDiscount = 1.0 - loyalty * 0.15            // 0.85 ... 1.00
        let effectiveAsk = Double(marketValue) * askMultiplier * loyaltyDiscount

        // Years verdict (sweet spot 3-4)
        let yearsVerdict: Verdict
        switch draft.years {
        case 1, 2:        yearsVerdict = aggression > 0.6 ? .tooLow : .fair
        case 3, 4:        yearsVerdict = .great
        case 5:           yearsVerdict = .fair
        default:          yearsVerdict = aggression > 0.4 ? .great : .fair  // 6-7yr: long-term security
        }

        // Base salary verdict (relative to 65% of effective ask, the typical base portion)
        let baseTarget = effectiveAsk * 0.65
        let baseVerdict = verdict(actual: Double(draft.baseSalary), target: baseTarget)

        // Signing bonus verdict (target ~ effective ask annual * 1.0 as one-time)
        let bonusTarget = effectiveAsk * 1.0
        let bonusVerdict = verdict(actual: Double(draft.signingBonus), target: bonusTarget)

        // Guarantee verdict — aggressive agents care most about this
        let guaranteeTarget = effectiveAsk * Double(draft.years) * (0.40 + aggression * 0.30)
        let guaranteeVerdict = verdict(actual: Double(draft.guaranteed), target: guaranteeTarget)

        // Overall score: weighted blend of the four verdicts
        let scores = [
            score(of: yearsVerdict)       * 0.15,
            score(of: baseVerdict)        * 0.30,
            score(of: bonusVerdict)       * 0.20,
            score(of: guaranteeVerdict)   * 0.35
        ]
        let overall = scores.reduce(0, +)

        // Counter-suggestion only when not already great enough
        let accepted = overall >= 0.85 &&
                       guaranteeVerdict != .tooLow &&
                       baseVerdict != .tooLow

        let counter: OfferDraft? = accepted ? nil : OfferDraft(
            years: max(draft.years, 3),
            baseSalary: max(draft.baseSalary, Int(baseTarget)),
            signingBonus: max(draft.signingBonus, Int(bonusTarget)),
            guaranteed: max(draft.guaranteed, Int(guaranteeTarget)),
            incentives: draft.incentives
        )

        let quote = quote(
            overall: overall,
            yearsVerdict: yearsVerdict,
            baseVerdict: baseVerdict,
            bonusVerdict: bonusVerdict,
            guaranteeVerdict: guaranteeVerdict,
            aggression: aggression,
            loyalty: loyalty
        )

        return AgentFeedback(
            yearsVerdict: yearsVerdict,
            baseVerdict: baseVerdict,
            bonusVerdict: bonusVerdict,
            guaranteeVerdict: guaranteeVerdict,
            overallScore: overall,
            counterSuggestion: counter,
            agentQuote: quote
        )
    }

    // MARK: - Private helpers

    private static func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }

    private static func verdict(actual: Double, target: Double) -> Verdict {
        guard target > 0 else { return .fair }
        let ratio = actual / target
        if ratio >= 1.05 { return .great }
        if ratio >= 0.85 { return .fair }
        return .tooLow
    }

    private static func score(of verdict: Verdict) -> Double {
        switch verdict {
        case .tooLow: return 0.2
        case .fair:   return 0.65
        case .great:  return 1.0
        }
    }

    private static func quote(
        overall: Double,
        yearsVerdict: Verdict,
        baseVerdict: Verdict,
        bonusVerdict: Verdict,
        guaranteeVerdict: Verdict,
        aggression: Double,
        loyalty: Double
    ) -> String {
        if overall >= 0.85 {
            if loyalty > 0.7 {
                return "My client wants to be here. Let's get this done."
            }
            return "We can work with this. Send the paperwork."
        }
        if guaranteeVerdict == .tooLow {
            return aggression > 0.6
                ? "We need real guarantees, or we're walking."
                : "More guarantees would help us close this."
        }
        if baseVerdict == .tooLow {
            return "Base salary needs to come up — significantly."
        }
        if bonusVerdict == .tooLow {
            return "Where's the signing bonus? My client has bills."
        }
        if yearsVerdict == .tooLow {
            return "We're looking for long-term security."
        }
        return "Let's see what else you can do."
    }
}
