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
            .filter { $0.contractYearsRemaining == 0 }
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
}
