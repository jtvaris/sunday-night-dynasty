import Foundation
import SwiftData

/// Manages the free-agent market: building the pool, signing players,
/// and simulating AI team signings.
enum FreeAgencyEngine {

    // MARK: - Types

    struct FreeAgent {
        let player: Player
        /// Desired annual salary in thousands.
        let askingPrice: Int
        /// Preferred contract length in years.
        let desiredYears: Int
        /// How many teams are interested (1-10 scale). Higher means bidding war.
        let marketInterest: Int
    }

    // MARK: - Market Generation

    /// Build the free-agent market from all players whose contracts have expired.
    /// Asking prices are influenced by market value and the player's personality motivation.
    static func generateFreeAgentMarket(allPlayers: [Player]) -> [FreeAgent] {
        allPlayers
            .filter { $0.contractYearsRemaining == 0 && !$0.isFranchiseTagged }
            .map { player in
                let baseValue = ContractEngine.estimateMarketValue(player: player)

                // Motivation-based salary modifier
                let motivationMultiplier: Double = {
                    switch player.personality.motivation {
                    case .money:
                        return 1.2   // Wants top dollar
                    case .winning:
                        return 0.9   // Will take a discount for a contender
                    case .stats:
                        return 1.05  // Wants a system where they'll produce
                    case .loyalty:
                        return 0.85  // Discount to stay with current team
                    case .fame:
                        return 1.1   // Big market premium
                    }
                }()

                let askingPrice = max(Int(Double(baseValue) * motivationMultiplier), 750)

                // Desired years: younger players want longer deals, older want shorter
                let desiredYears: Int = {
                    let age = player.age
                    let peak = player.position.peakAgeRange
                    if age < peak.lowerBound {
                        return Int.random(in: 3...5)
                    } else if age <= peak.upperBound {
                        return Int.random(in: 2...4)
                    } else {
                        return Int.random(in: 1...2)
                    }
                }()

                // Market interest driven by overall rating
                let interest: Int = {
                    let ovr = player.overall
                    switch ovr {
                    case 90...99: return Int.random(in: 7...10)
                    case 80...89: return Int.random(in: 5...8)
                    case 70...79: return Int.random(in: 3...6)
                    case 60...69: return Int.random(in: 1...4)
                    default:      return 1
                    }
                }()

                return FreeAgent(
                    player: player,
                    askingPrice: askingPrice,
                    desiredYears: desiredYears,
                    marketInterest: interest
                )
            }
    }

    // MARK: - Signing

    /// Sign a free agent to a team. Works in both simple and realistic cap modes.
    /// In realistic mode a full Contract is created and inserted into the model context.
    static func signFreeAgent(
        player: Player,
        team: Team,
        years: Int,
        salary: Int,
        capMode: CapMode,
        modelContext: ModelContext
    ) {
        switch capMode {
        case .simple:
            ContractEngine.signPlayerSimple(
                player: player,
                years: years,
                annualSalary: salary,
                team: team
            )

        case .realistic:
            // Build a flat base-salary structure for the realistic contract.
            let baseSalaries = Array(repeating: salary, count: years)
            let signingBonus = Int(Double(salary) * 0.3) * years  // ~30% of total as bonus
            let guaranteed = salary * max(years / 2, 1)           // roughly half the deal

            let contract = ContractEngine.createContract(
                playerID: player.id,
                teamID: team.id,
                years: years,
                baseSalaries: baseSalaries,
                signingBonus: signingBonus,
                guaranteed: guaranteed,
                noTrade: false
            )

            modelContext.insert(contract)

            player.contractYearsRemaining = years
            player.annualSalary = salary
            player.teamID = team.id
            team.currentCapUsage += contract.capHit
        }
    }

    // MARK: - New League Year Transition

    struct LeagueYearSummary {
        let newFreeAgents: [(name: String, position: String, overall: Int, formerTeam: String)]
        let playerTeamCapBefore: Int
        let playerTeamCapAfter: Int
        let capFreed: Int
        let notableFreeAgents: [(name: String, position: String, overall: Int)]
        let totalFreeAgentCount: Int
    }

    /// Advance all contracts by one year. Players whose contracts expire become free agents.
    /// Returns a summary for display.
    static func executeNewLeagueYear(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        modelContext: ModelContext
    ) -> LeagueYearSummary {
        let playerTeam = allTeams.first { $0.id == playerTeamID }
        let capBefore = playerTeam?.currentCapUsage ?? 0

        var newFAs: [(name: String, position: String, overall: Int, formerTeam: String)] = []

        for player in allPlayers {
            guard player.contractYearsRemaining > 0, !player.isFranchiseTagged else { continue }

            player.contractYearsRemaining -= 1

            if player.contractYearsRemaining == 0 {
                // Player's contract has expired — becomes free agent
                let formerTeam = allTeams.first { $0.id == player.teamID }
                let teamAbbr = formerTeam?.abbreviation ?? "FA"

                newFAs.append((
                    name: player.fullName,
                    position: player.position.rawValue,
                    overall: player.overall,
                    formerTeam: teamAbbr
                ))

                // Remove from team cap
                if let team = formerTeam {
                    team.currentCapUsage -= player.annualSalary
                }
                player.teamID = nil
                player.annualSalary = 0
            }
        }

        // Remove franchise tags (they last one year)
        for player in allPlayers where player.isFranchiseTagged {
            player.isFranchiseTagged = false
        }

        // Apply cap growth (~5-8% increase)
        let capGrowth = Double.random(in: 0.05...0.08)
        for team in allTeams {
            team.salaryCap = Int(Double(team.salaryCap) * (1.0 + capGrowth))
        }

        let capAfter = playerTeam?.currentCapUsage ?? 0
        let capFreed = capBefore - capAfter

        // Sort by overall for notable FAs
        let sortedFAs = newFAs.sorted { $0.overall > $1.overall }
        let notable = sortedFAs.prefix(10).map { (name: $0.name, position: $0.position, overall: $0.overall) }

        return LeagueYearSummary(
            newFreeAgents: sortedFAs,
            playerTeamCapBefore: capBefore,
            playerTeamCapAfter: capAfter,
            capFreed: capFreed,
            notableFreeAgents: notable,
            totalFreeAgentCount: newFAs.count
        )
    }

    // MARK: - Skip Remaining FA

    /// AI signs all remaining free agents to fill team rosters.
    static func simulateRemainingFA(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID?,
        modelContext: ModelContext
    ) {
        let freeAgents = generateFreeAgentMarket(allPlayers: allPlayers)
        let aiTeams = allTeams.filter { $0.id != playerTeamID }
        simulateAIFreeAgency(freeAgents: freeAgents, teams: aiTeams, modelContext: modelContext)
    }

    // MARK: - AI Free Agency Simulation

    /// Let AI-controlled teams sign available free agents based on need and cap room.
    static func simulateAIFreeAgency(
        freeAgents: [FreeAgent],
        teams: [Team],
        modelContext: ModelContext
    ) {
        // Sort free agents by overall (best first) so elite players go first
        let sortedAgents = freeAgents.sorted { $0.player.overall > $1.player.overall }

        for agent in sortedAgents {
            // Skip players who were already signed this cycle
            guard agent.player.teamID == nil else { continue }

            // Find teams with enough cap space, sorted by most available cap
            let eligibleTeams = teams
                .filter { $0.availableCap >= agent.askingPrice }
                .sorted { $0.availableCap > $1.availableCap }

            // Pick from the top interested teams (capped by marketInterest)
            let candidateCount = min(agent.marketInterest, eligibleTeams.count)
            guard candidateCount > 0 else { continue }

            let candidates = Array(eligibleTeams.prefix(candidateCount))

            // Randomly select a winner from the candidate pool
            guard let winningTeam = candidates.randomElement() else { continue }

            // AI always signs at a slight discount (negotiation)
            let agreedSalary = max(Int(Double(agent.askingPrice) * Double.random(in: 0.85...1.0)), 750)
            let agreedYears = agent.desiredYears

            // Use simple mode for AI signings to keep simulation fast
            ContractEngine.signPlayerSimple(
                player: agent.player,
                years: agreedYears,
                annualSalary: agreedSalary,
                team: winningTeam
            )
        }
    }

    // MARK: - AI Bidding Per Round

    struct AIBid {
        let teamID: UUID
        let teamAbbr: String
        let salary: Int
        let years: Int
    }

    /// Generate AI team offers for each free agent in a given round.
    /// Returns a dictionary keyed by player ID with arrays of competing bids.
    static func generateAIOffers(
        freeAgents: [FreeAgent],
        round: Int,
        allTeams: [Team],
        playerTeamID: UUID?
    ) -> [UUID: [AIBid]] {
        let aggression = FreeAgencyStep.aiAggression(round)
        var offers: [UUID: [AIBid]] = [:]

        // Target different OVR tiers by round
        let targetMinOVR: Int = {
            switch round {
            case 1: return 85
            case 2: return 80
            case 3: return 75
            case 4: return 70
            case 5: return 65
            default: return 60
            }
        }()

        let aiTeams = allTeams.filter { $0.id != playerTeamID }

        for fa in freeAgents {
            guard fa.player.teamID == nil else { continue }
            guard fa.player.overall >= targetMinOVR else { continue }

            // Number of teams bidding scales with aggression and player quality
            let qualityFactor = Double(fa.player.overall - 60) / 40.0
            let bidCount = max(1, Int(aggression * qualityFactor * 5))

            let eligibleTeams = aiTeams
                .filter { $0.availableCap >= fa.askingPrice }
                .shuffled()
                .prefix(bidCount)

            var bids: [AIBid] = []
            for team in eligibleTeams {
                let salaryMultiplier = Double.random(in: (aggression * 0.8)...(aggression * 1.1 + 0.1))
                let offeredSalary = max(Int(Double(fa.askingPrice) * salaryMultiplier), 750)
                bids.append(AIBid(
                    teamID: team.id,
                    teamAbbr: team.abbreviation,
                    salary: offeredSalary,
                    years: fa.desiredYears
                ))
            }

            if !bids.isEmpty {
                offers[fa.player.id] = bids
            }
        }

        return offers
    }

    // MARK: - Player Decision

    struct PlayerDecision {
        let accepted: Bool
        let chosenTeamID: UUID?
        let chosenTeamName: String?
        let reason: String          // ALWAYS populated
        let salary: Int?
        let years: Int?
    }

    /// Determine a free agent's decision given the player's offer and AI bids.
    /// The reason is always populated explaining why the player chose or rejected.
    static func resolvePlayerDecision(
        player: Player,
        playerOffer: (salary: Int, years: Int)?,
        aiBids: [AIBid],
        round: Int
    ) -> PlayerDecision {
        // Combine player offer with AI bids
        struct Bid {
            let teamID: UUID?
            let teamName: String
            let salary: Int
            let years: Int
            let isPlayer: Bool
        }

        var allBids: [Bid] = aiBids.map {
            Bid(teamID: $0.teamID, teamName: $0.teamAbbr, salary: $0.salary, years: $0.years, isPlayer: false)
        }

        if let offer = playerOffer {
            allBids.append(Bid(teamID: nil, teamName: "Your Team", salary: offer.salary, years: offer.years, isPlayer: true))
        }

        guard !allBids.isEmpty else {
            return PlayerDecision(
                accepted: false,
                chosenTeamID: nil,
                chosenTeamName: nil,
                reason: "No offers received \u{2014} will wait for better opportunities",
                salary: nil,
                years: nil
            )
        }

        // Score each bid based on player motivation
        func scoreBid(_ bid: Bid) -> Double {
            var score = Double(bid.salary)

            switch player.personality.motivation {
            case .money:
                score *= 1.3  // Weighs salary heavily
            case .winning:
                // Would need team win data; use salary as proxy + bonus for player's team
                score *= bid.isPlayer ? 1.15 : 1.0
            case .stats:
                score *= 1.05
            case .loyalty:
                score *= bid.isPlayer ? 1.25 : 0.9
            case .fame:
                score *= 1.1
            }

            // Player team loyalty bonus
            if bid.isPlayer {
                score *= 1.1
            }

            // Longer deals valued more by young players
            if player.age < player.position.peakAgeRange.lowerBound {
                score *= 1.0 + Double(bid.years) * 0.05
            }

            return score
        }

        let scoredBids = allBids.map { (bid: $0, score: scoreBid($0)) }
        let best = scoredBids.max(by: { $0.score < $1.score })!

        if best.bid.isPlayer {
            return PlayerDecision(
                accepted: true,
                chosenTeamID: nil,
                chosenTeamName: "Your Team",
                reason: playerAcceptReason(player: player),
                salary: best.bid.salary,
                years: best.bid.years
            )
        } else {
            return PlayerDecision(
                accepted: false,
                chosenTeamID: best.bid.teamID,
                chosenTeamName: best.bid.teamName,
                reason: playerRejectReason(player: player, chosenTeam: best.bid.teamName, salary: best.bid.salary, playerOffer: playerOffer),
                salary: best.bid.salary,
                years: best.bid.years
            )
        }
    }

    // MARK: - Media Headlines

    /// Generate media headlines for a round's signings and rejections.
    static func generateHeadlines(
        signings: [(playerName: String, position: String, team: String, salary: Int)],
        rejections: [(playerName: String, chosenTeam: String?)],
        playerTeamAbbr: String,
        round: Int
    ) -> [String] {
        var headlines: [String] = []

        // Big signing headlines
        for signing in signings.prefix(3) {
            let salaryM = String(format: "%.1f", Double(signing.salary) / 1000.0)
            let templates = [
                "\(signing.team) land \(signing.playerName) in $\(salaryM)M deal",
                "\(signing.playerName) signs with \(signing.team) \u{2014} \(signing.position) market heats up",
                "Breaking: \(signing.team) add \(signing.playerName) to bolster roster",
            ]
            headlines.append(templates.randomElement()!)
        }

        // Player team rejection headlines
        for rejection in rejections.prefix(2) {
            if let team = rejection.chosenTeam {
                let templates = [
                    "Surprise: \(playerTeamAbbr) lose out on \(rejection.playerName) to \(team)",
                    "\(rejection.playerName) spurns \(playerTeamAbbr), signs elsewhere",
                    "\(playerTeamAbbr) miss on \(rejection.playerName) \u{2014} \(team) swoop in",
                ]
                headlines.append(templates.randomElement()!)
            }
        }

        // Round-specific flavor
        switch round {
        case 1:
            headlines.append("Day 1 frenzy: Top free agents fly off the board")
        case 2:
            headlines.append("Day 2: Market still active as teams fill key needs")
        case 3:
            headlines.append("Day 3: Mid-tier market opens with value deals")
        case 4:
            headlines.append("Week 2: Free agency slows as rosters take shape")
        case 5:
            headlines.append("Week 3: Bargain hunters find remaining gems")
        case 6:
            headlines.append("Week 4: Final scraps as teams wrap up FA spending")
        default:
            break
        }

        return headlines
    }

    // MARK: - Decision Reasons (always visible)

    private static func playerAcceptReason(player: Player) -> String {
        switch player.personality.motivation {
        case .money:   return "Excited about the financial commitment"
        case .winning: return "Believes this team can compete for a championship"
        case .stats:   return "Sees a clear path to a bigger role here"
        case .loyalty: return "Excited to stay and build something special here"
        case .fame:    return "Happy with the opportunity and exposure"
        }
    }

    private static func playerRejectReason(
        player: Player,
        chosenTeam: String,
        salary: Int,
        playerOffer: (salary: Int, years: Int)?
    ) -> String {
        let teamLabel = chosenTeam

        switch player.personality.motivation {
        case .money:
            if let offer = playerOffer {
                let diff = salary - offer.salary
                if diff > 0 {
                    let millions = Double(diff) / 1000.0
                    return "Chose \(teamLabel) \u{2014} offered $\(String(format: "%.1f", millions))M more per year"
                }
            }
            return "Chose \(teamLabel) for a more lucrative deal"
        case .winning:
            return "Chose \(teamLabel) for championship contention"
        case .stats:
            return "Chose \(teamLabel) for a larger role and more playing time"
        case .loyalty:
            return "Chose \(teamLabel) to return to familiar surroundings"
        case .fame:
            return "Chose \(teamLabel) for the big market spotlight"
        }
    }
}
