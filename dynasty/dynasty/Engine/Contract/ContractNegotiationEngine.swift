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

    /// Total contract value in thousands.
    var totalValue: Int { annualSalary * years + signingBonus }

    /// Guaranteed money in thousands.
    var guaranteedMoney: Int { Int(Double(totalValue) * Double(guaranteedPercent) / 100.0) }

    /// Annual cap hit including prorated signing bonus.
    var annualCapHit: Int {
        let proratedBonus = years > 0 ? signingBonus / years : 0
        return annualSalary + proratedBonus
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
}

// MARK: - Negotiation Context

enum NegotiationType {
    case extend    // Extending current player's contract
    case freeAgent // Signing a free agent
}

// MARK: - Negotiation Engine

/// Handles the logic of contract negotiations between GM and player agent.
/// Agent evaluates offers based on market value, player age, morale, and team factors.
enum ContractNegotiationEngine {

    // MARK: - Generate Agent's Opening Demand

    /// Creates the agent's initial asking price based on player profile.
    static func generateOpeningDemand(
        player: Player,
        negotiationType: NegotiationType,
        teamCapSpace: Int = 50_000
    ) -> (offer: NegotiationOffer, message: String) {
        let marketValue = ContractEngine.estimateMarketValue(player: player)

        // Agent asks 10-25% above market value
        let aggressiveness = Double.random(in: 1.10...1.25)
        let askingSalary = Int(Double(marketValue) * aggressiveness)

        // Preferred years based on age
        let preferredYears: Int = {
            switch player.age {
            case ...25: return Int.random(in: 3...4)   // Young: shorter for next payday
            case 26...29: return Int.random(in: 3...5)  // Prime: medium-long
            case 30...32: return Int.random(in: 2...4)  // Aging: wants security
            default: return Int.random(in: 1...2)       // Old: short prove-it
            }
        }()

        // Signing bonus: 15-30% of first year salary
        let bonusPercent = Double.random(in: 0.15...0.30)
        let signingBonus = Int(Double(askingSalary) * bonusPercent)

        // Guaranteed percentage based on OVR
        let guaranteedPercent: Int = {
            switch player.overall {
            case 90...: return Int.random(in: 60...80)  // Elite: high guarantees
            case 80..<90: return Int.random(in: 45...65)
            case 70..<80: return Int.random(in: 30...50)
            default: return Int.random(in: 20...35)
            }
        }()

        // No-trade clause for elite players
        let noTrade = player.overall >= 90 && Bool.random()

        let offer = NegotiationOffer(
            years: preferredYears,
            annualSalary: askingSalary,
            signingBonus: signingBonus,
            guaranteedPercent: guaranteedPercent,
            noTradeClause: noTrade
        )

        let message = generateOpeningMessage(player: player, offer: offer, type: negotiationType)
        return (offer, message)
    }

    // MARK: - Evaluate Counter Offer

    /// Agent evaluates the GM's counter-offer and responds.
    /// Returns the agent's response message, optional counter-offer, and whether a deal is reached.
    static func evaluateCounterOffer(
        gmOffer: NegotiationOffer,
        player: Player,
        previousAgentOffer: NegotiationOffer,
        roundNumber: Int,
        negotiationType: NegotiationType
    ) -> (message: String, counterOffer: NegotiationOffer?, outcome: NegotiationOutcome) {
        let marketValue = ContractEngine.estimateMarketValue(player: player)
        let askingTotal = previousAgentOffer.totalValue
        let offerTotal = gmOffer.totalValue

        // Calculate how close the offer is to asking price (0.0 = nothing, 1.0 = full ask)
        let offerRatio = Double(offerTotal) / Double(max(1, askingTotal))

        // Morale affects willingness (happy players accept slightly less)
        let moraleFactor: Double = {
            switch player.morale {
            case 85...: return 0.05   // Happy: slightly more willing
            case 70..<85: return 0.0
            case 55..<70: return -0.03
            default: return -0.08     // Unhappy: harder to sign
            }
        }()

        // Loyalty factor for extensions (longer on team = more willing)
        let loyaltyFactor: Double = negotiationType == .extend ? 0.03 : 0.0

        let adjustedRatio = offerRatio + moraleFactor + loyaltyFactor

        // Check guarantees — agent won't accept much below their ask
        let guaranteeGap = previousAgentOffer.guaranteedPercent - gmOffer.guaranteedPercent
        let guaranteePenalty = guaranteeGap > 15 ? -0.05 : 0.0

        let effectiveRatio = adjustedRatio + guaranteePenalty

        // Decision logic
        if effectiveRatio >= 0.95 {
            // Accept the deal
            let message = generateAcceptMessage(player: player, offer: gmOffer)
            return (message, nil, .dealReached(gmOffer))
        }

        if effectiveRatio >= 0.85 {
            // Counter with a compromise (split the difference)
            let counterOffer = generateCompromise(
                gmOffer: gmOffer,
                agentAsk: previousAgentOffer,
                splitFactor: 0.6 // Agent moves 40%, expects GM to move 60%
            )
            let message = generateCounterMessage(player: player, tone: .reasonable, round: roundNumber)
            return (message, counterOffer, .pending)
        }

        if effectiveRatio >= 0.75 {
            // Counter but express disappointment
            let counterOffer = generateCompromise(
                gmOffer: gmOffer,
                agentAsk: previousAgentOffer,
                splitFactor: 0.75 // Agent barely moves
            )
            let message = generateCounterMessage(player: player, tone: .disappointed, round: roundNumber)
            return (message, counterOffer, .pending)
        }

        if roundNumber >= 3 || effectiveRatio < 0.65 {
            // Walk away — offer is too low or negotiations stalled
            let message = generateWalkAwayMessage(player: player, ratio: effectiveRatio)
            return (message, nil, .playerWalked)
        }

        // Low but still talking
        let counterOffer = generateCompromise(
            gmOffer: gmOffer,
            agentAsk: previousAgentOffer,
            splitFactor: 0.85 // Agent barely budges
        )
        let message = generateCounterMessage(player: player, tone: .insulted, round: roundNumber)
        return (message, counterOffer, .pending)
    }

    // MARK: - Compromise Generator

    private static func generateCompromise(
        gmOffer: NegotiationOffer,
        agentAsk: NegotiationOffer,
        splitFactor: Double  // 0.5 = meet in middle, 0.8 = agent barely moves
    ) -> NegotiationOffer {
        let salary = Int(Double(agentAsk.annualSalary) * splitFactor + Double(gmOffer.annualSalary) * (1.0 - splitFactor))
        let bonus = Int(Double(agentAsk.signingBonus) * splitFactor + Double(gmOffer.signingBonus) * (1.0 - splitFactor))
        let guaranteed = Int(Double(agentAsk.guaranteedPercent) * splitFactor + Double(gmOffer.guaranteedPercent) * (1.0 - splitFactor))

        // Years: agent usually holds firm on years
        let years = agentAsk.years

        return NegotiationOffer(
            years: years,
            annualSalary: salary,
            signingBonus: bonus,
            guaranteedPercent: min(100, guaranteed),
            noTradeClause: agentAsk.noTradeClause
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

    private static func generateCounterMessage(player: Player, tone: Tone, round: Int) -> String {
        let name = player.firstName
        switch tone {
        case .reasonable:
            let msgs = [
                "We appreciate the offer. We're getting closer — here's where we can meet you.",
                "\(name) wants to make this work. We've adjusted our ask. Take a look.",
                "Good progress. Here's a revised number that works for both sides."
            ]
            return msgs.randomElement()!
        case .disappointed:
            let msgs = [
                "Honestly, we expected more given \(name)'s production. Here's our bottom line.",
                "That's below what the market bears. We've come down, but there's a floor here.",
                "\(name) is disappointed but willing to negotiate. This is our revised ask."
            ]
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

    private static func generateAcceptMessage(player: Player, offer: NegotiationOffer) -> String {
        let name = player.firstName
        let totalM = formatMillions(offer.totalValue)
        let msgs = [
            "\(name) is thrilled to stay. \(offer.years) years, \(totalM) total — we have a deal!",
            "We're happy with this. \(name) can't wait to get back to work. Deal done!",
            "That works for us. \(name) is committed to this team. Let's make it official."
        ]
        return msgs.randomElement()!
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
