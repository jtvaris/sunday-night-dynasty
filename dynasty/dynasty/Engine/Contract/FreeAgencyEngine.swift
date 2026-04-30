import Foundation
import SwiftData

/// Manages the free-agent market: building the pool, signing players,
/// and simulating AI team signings with realistic bidding wars.
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

    // MARK: - Position Need Levels (for AI bidding)

    enum PositionNeedLevel: String {
        case critical = "Critical"  // No starter-quality player
        case high     = "High"      // Below ideal depth
        case moderate = "Moderate"  // Could use depth
        case none     = "None"      // Fully stocked
    }

    // MARK: - Bidding Update (shown to player between rounds)

    struct BiddingUpdate {
        let playerID: UUID
        let playerName: String
        let position: String
        let yourOffer: Int
        let yourYears: Int
        let highestCompetingOffer: Int?    // approximate, not exact
        let highestCompetingTeam: String?  // team abbreviation
        let totalBidders: Int
        let playerLeaning: PlayerLeaning
        let isBiddingWar: Bool
    }

    enum PlayerLeaning: String {
        case prefersYou     = "Player prefers your team"
        case leaningAway    = "Player is leaning toward another team"
        case undecided      = "Player is weighing options"
        case strongInterest = "Player has strong interest in your offer"
    }

    // MARK: - Instant Signing Result

    enum InstantSigningResult {
        case signedImmediately  // >= 1.4x on Day 1
        case coinFlipSigned     // >= 1.2x on Day 1, 50% chance
        case goesToMarket       // Normal bidding process
    }

    // MARK: - Market Generation

    /// Build the free-agent market from all players whose contracts have expired.
    /// Asking prices are influenced by market value and the player's personality motivation.
    static func generateFreeAgentMarket(allPlayers: [Player], salaryCap: Int = 265_000) -> [FreeAgent] {
        allPlayers
            .filter { $0.contractYearsRemaining == 0 && !$0.isFranchiseTagged }
            .map { player in
                let baseValue = ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)

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

                let minimum = max(Int(0.0028 * Double(salaryCap)), 750)
                let askingPrice = max(Int(Double(baseValue) * motivationMultiplier), minimum)

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

    /// Sign a free agent to a team. Works in all cap modes.
    /// - Simple: writes annual salary into team cap usage.
    /// - Realistic: builds a full Contract with escalating/front-loaded structure.
    /// - Sandbox: stamps the player onto the roster but skips any cap accounting,
    ///   so the team can sign unlimited players regardless of cap room.
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
            // Build a realistic contract with proper salary structure
            let contract = ContractEngine.buildRealisticContract(
                playerID: player.id,
                teamID: team.id,
                annualSalary: salary,
                years: years,
                playerAge: player.age,
                noTrade: false
            )

            modelContext.insert(contract)

            player.contractYearsRemaining = years
            player.annualSalary = salary
            player.teamID = team.id
            team.currentCapUsage += contract.capHit

        case .sandbox:
            // Sandbox: assign the player to the team without touching cap usage.
            // Salary is recorded for display purposes but never debits the cap.
            player.contractYearsRemaining = years
            player.annualSalary = salary
            player.teamID = team.id
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
                // Player's contract has expired -- becomes free agent
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
        modelContext: ModelContext,
        capMode: CapMode = .simple
    ) {
        // Use average cap across all teams for market valuation
        let avgCap = allTeams.isEmpty ? 265_000 : allTeams.reduce(0) { $0 + $1.salaryCap } / allTeams.count
        let freeAgents = generateFreeAgentMarket(allPlayers: allPlayers, salaryCap: avgCap)
        let aiTeams = allTeams.filter { $0.id != playerTeamID }
        simulateAIFreeAgency(freeAgents: freeAgents, teams: aiTeams, modelContext: modelContext, capMode: capMode)
    }

    // MARK: - AI Free Agency Simulation

    /// Let AI-controlled teams sign available free agents based on need and cap room.
    /// In sandbox cap mode the cap-room filter is dropped so any team can sign anyone.
    static func simulateAIFreeAgency(
        freeAgents: [FreeAgent],
        teams: [Team],
        modelContext: ModelContext,
        capMode: CapMode = .simple
    ) {
        // Sort free agents by overall (best first) so elite players go first
        let sortedAgents = freeAgents.sorted { $0.player.overall > $1.player.overall }

        for agent in sortedAgents {
            // Skip players who were already signed this cycle
            guard agent.player.teamID == nil else { continue }

            // In sandbox mode, every team is eligible regardless of cap.
            let eligibleTeams: [Team]
            switch capMode {
            case .simple, .realistic:
                eligibleTeams = teams
                    .filter { $0.availableCap >= agent.askingPrice }
                    .sorted { $0.availableCap > $1.availableCap }
            case .sandbox:
                eligibleTeams = teams.shuffled()
            }

            // Pick from the top interested teams (capped by marketInterest)
            let candidateCount = min(agent.marketInterest, eligibleTeams.count)
            guard candidateCount > 0 else { continue }

            let candidates = Array(eligibleTeams.prefix(candidateCount))

            // Randomly select a winner from the candidate pool
            guard let winningTeam = candidates.randomElement() else { continue }

            // AI always signs at a slight discount (negotiation)
            let minimum = max(Int(0.0028 * Double(winningTeam.salaryCap)), 750)
            let agreedSalary = max(Int(Double(agent.askingPrice) * Double.random(in: 0.85...1.0)), minimum)
            let agreedYears = agent.desiredYears

            // Route the signing through the cap-mode-aware wrapper so sandbox
            // skips cap accounting entirely.
            ContractEngine.signPlayer(
                player: agent.player,
                years: agreedYears,
                annualSalary: agreedSalary,
                team: winningTeam,
                capMode: capMode
            )
        }
    }

    // MARK: - AI Position Need Assessment

    /// Calculate how badly an AI team needs a specific position.
    /// Compares current roster to ideal depth chart.
    static func assessPositionNeed(team: Team, position: Position, allPlayers: [Player]) -> PositionNeedLevel {
        let teamPlayers = allPlayers.filter { $0.teamID == team.id }

        // Map positions to their group and ideal counts
        let (groupPositions, idealCount) = positionGroupInfo(for: position)

        let groupPlayers = teamPlayers.filter { groupPositions.contains($0.position) }
        let count = groupPlayers.count
        let bestOVR = groupPlayers.map(\.overall).max() ?? 0

        // Critical: no starter-quality player at the position
        if count == 0 || bestOVR < 60 {
            return .critical
        }

        let deficit = idealCount - count

        // High need: significant roster holes
        if deficit >= 2 || (deficit >= 1 && bestOVR < 70) {
            return .high
        }

        // Moderate: could use depth
        if deficit >= 1 || bestOVR < 75 {
            return .moderate
        }

        return .none
    }

    /// Returns the position group and ideal roster count for a given position.
    private static func positionGroupInfo(for position: Position) -> (positions: [Position], idealCount: Int) {
        switch position {
        case .QB:                    return ([.QB], 2)
        case .RB, .FB:               return ([.RB, .FB], 3)
        case .WR:                    return ([.WR], 4)
        case .TE:                    return ([.TE], 2)
        case .LT, .LG, .C, .RG, .RT: return ([.LT, .LG, .C, .RG, .RT], 8)
        case .DE:                    return ([.DE], 3)
        case .DT:                    return ([.DT], 3)
        case .OLB, .MLB:            return ([.OLB, .MLB], 5)
        case .CB:                    return ([.CB], 4)
        case .FS, .SS:              return ([.FS, .SS], 3)
        case .K:                     return ([.K], 1)
        case .P:                     return ([.P], 1)
        }
    }

    /// Multiplier AI teams apply based on how badly they need the position.
    private static func needMultiplier(for need: PositionNeedLevel) -> ClosedRange<Double> {
        switch need {
        case .critical: return 1.3...1.5
        case .high:     return 1.1...1.3
        case .moderate: return 0.95...1.1
        case .none:     return 0.0...0.0  // Won't bid
        }
    }

    // MARK: - AI Bidding Per Round (Need-Based)

    struct AIBid {
        let teamID: UUID
        let teamAbbr: String
        let salary: Int
        let years: Int
        let needLevel: PositionNeedLevel
    }

    /// Generate AI team offers for each free agent in a given round.
    /// AI teams now bid based on positional need and cap space.
    /// Returns a dictionary keyed by player ID with arrays of competing bids.
    /// In sandbox cap mode the cap-room precondition is dropped so any team can bid.
    static func generateAIOffers(
        freeAgents: [FreeAgent],
        round: Int,
        allTeams: [Team],
        allPlayers: [Player]? = nil,
        playerTeamID: UUID?,
        capMode: CapMode = .simple
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
        // All players for need assessment; fall back to empty if not provided
        let rosterPlayers = allPlayers ?? []

        for fa in freeAgents {
            guard fa.player.teamID == nil else { continue }
            guard fa.player.overall >= targetMinOVR else { continue }

            var bids: [AIBid] = []

            for team in aiTeams {
                // Skip cap gating entirely in sandbox mode.
                if capMode != .sandbox {
                    guard team.availableCap >= fa.askingPrice else { continue }
                }

                // Assess this team's need for the player's position
                let need: PositionNeedLevel
                if rosterPlayers.isEmpty {
                    // Fallback: use old quality-based approach when roster data unavailable
                    let qualityFactor = Double(fa.player.overall - 60) / 40.0
                    if qualityFactor > 0.5 { need = .high }
                    else if qualityFactor > 0.25 { need = .moderate }
                    else { need = .none }
                } else {
                    need = assessPositionNeed(team: team, position: fa.player.position, allPlayers: rosterPlayers)
                }

                // Teams with no need don't bid on that position
                guard need != .none else { continue }

                // Need-based multiplier
                let needRange = needMultiplier(for: need)
                let needFactor = Double.random(in: needRange)

                // Combine need with round aggression
                let salaryMultiplier = needFactor * Double.random(in: (aggression * 0.85)...(aggression * 1.05 + 0.05))

                // Cap-aware: don't bid more than 30% of remaining cap on one player.
                // Sandbox skips this clamp so bids reflect raw demand only.
                let minimum = max(Int(0.0028 * Double(team.salaryCap)), 750)
                let rawOffer = Int(Double(fa.askingPrice) * salaryMultiplier)
                let offeredSalary: Int
                if capMode == .sandbox {
                    offeredSalary = max(rawOffer, minimum)
                } else {
                    let maxBid = Int(Double(team.availableCap) * 0.30)
                    offeredSalary = max(min(rawOffer, maxBid), minimum)
                }

                bids.append(AIBid(
                    teamID: team.id,
                    teamAbbr: team.abbreviation,
                    salary: offeredSalary,
                    years: fa.desiredYears,
                    needLevel: need
                ))
            }

            // Limit total bids per player based on quality + aggression
            let qualityFactor = Double(fa.player.overall - 60) / 40.0
            let maxBidders = max(1, Int(aggression * qualityFactor * 6))

            // Sort by salary descending so the most aggressive bidders are kept
            let sortedBids = bids.sorted { $0.salary > $1.salary }
            let cappedBids = Array(sortedBids.prefix(maxBidders))

            if !cappedBids.isEmpty {
                offers[fa.player.id] = cappedBids
            }
        }

        return offers
    }

    // MARK: - Instant Signing Check (Big Overpay)

    /// Check if an offer is high enough to trigger an instant signing.
    /// Offer >= 1.4x asking on Day 1 -> immediate signing.
    /// Offer >= 1.2x asking on Day 1 -> 50% chance of immediate signing.
    static func checkInstantSigning(
        offeredSalary: Int,
        askingPrice: Int,
        round: Int
    ) -> InstantSigningResult {
        guard round == 1 else { return .goesToMarket }

        let ratio = Double(offeredSalary) / Double(max(askingPrice, 1))

        if ratio >= 1.4 {
            return .signedImmediately
        } else if ratio >= 1.2 {
            return Bool.random() ? .coinFlipSigned : .goesToMarket
        }

        return .goesToMarket
    }

    // MARK: - Bidding War Detection

    struct BiddingWarInfo {
        let playerID: UUID
        let playerName: String
        let position: String
        let bidderCount: Int
        let escalatedPrice: Int   // Price after escalation
        let droppedOutTeams: [String]  // Teams that couldn't keep up
    }

    /// Detect and escalate bidding wars when 4+ teams bid on the same player.
    /// Returns escalated bids and info about which teams dropped out.
    /// In sandbox cap mode every team can afford every escalation.
    static func processBiddingWars(
        aiBids: inout [UUID: [AIBid]],
        freeAgents: [FreeAgent],
        allTeams: [Team],
        capMode: CapMode = .simple
    ) -> [BiddingWarInfo] {
        var wars: [BiddingWarInfo] = []

        for (playerID, bids) in aiBids {
            guard bids.count >= 4 else { continue }
            guard let fa = freeAgents.first(where: { $0.player.id == playerID }) else { continue }

            let bestOffer = bids.map(\.salary).max() ?? fa.askingPrice
            // Escalate 5-15% above best offer
            let escalation = Double.random(in: 1.05...1.15)
            let escalatedPrice = Int(Double(bestOffer) * escalation)

            // Some teams drop out if they can't afford the escalated price
            var survivingBids: [AIBid] = []
            var droppedOut: [String] = []

            for bid in bids {
                guard let team = allTeams.first(where: { $0.id == bid.teamID }) else { continue }
                let canAfford = (capMode == .sandbox) ? true : (team.availableCap >= escalatedPrice)
                // Critical-need teams push harder to stay in
                let staysIn: Bool
                if bid.needLevel == .critical {
                    staysIn = canAfford  // Always stays if they can afford it
                } else if bid.needLevel == .high {
                    staysIn = canAfford && Double.random(in: 0...1) > 0.2  // 80% stay
                } else {
                    staysIn = canAfford && Double.random(in: 0...1) > 0.5  // 50% stay
                }

                if staysIn {
                    // Raise their bid to compete
                    let raisedSalary = Int(Double(bid.salary) * escalation)
                    let clampedSalary = (capMode == .sandbox)
                        ? raisedSalary
                        : min(raisedSalary, team.availableCap)
                    survivingBids.append(AIBid(
                        teamID: bid.teamID,
                        teamAbbr: bid.teamAbbr,
                        salary: clampedSalary,
                        years: bid.years,
                        needLevel: bid.needLevel
                    ))
                } else {
                    droppedOut.append(bid.teamAbbr)
                }
            }

            aiBids[playerID] = survivingBids

            wars.append(BiddingWarInfo(
                playerID: playerID,
                playerName: fa.player.fullName,
                position: fa.player.position.rawValue,
                bidderCount: bids.count,
                escalatedPrice: escalatedPrice,
                droppedOutTeams: droppedOut
            ))
        }

        return wars
    }

    // MARK: - Generate Bidding Updates (for player UI)

    /// Generate bidding updates for all players the human has bid on.
    /// Shows approximate competing offers and player leanings.
    static func generateBiddingUpdates(
        myOffers: [UUID: (salary: Int, years: Int)],
        aiBids: [UUID: [AIBid]],
        freeAgents: [FreeAgent],
        playerTeamID: UUID?
    ) -> [BiddingUpdate] {
        var updates: [BiddingUpdate] = []

        for (playerID, offer) in myOffers {
            guard let fa = freeAgents.first(where: { $0.player.id == playerID }) else { continue }
            let player = fa.player
            let competingBids = aiBids[playerID] ?? []

            // Find highest competing offer (fuzz it slightly for realism)
            let bestCompeting = competingBids.max(by: { $0.salary < $1.salary })
            let fuzzedHighest: Int? = bestCompeting.map { bid in
                // Show approximate value (within 5-10%)
                let fuzz = Double.random(in: 0.93...1.07)
                return Int(Double(bid.salary) * fuzz)
            }

            // Determine player leaning based on motivation
            let leaning: PlayerLeaning = {
                guard let best = bestCompeting else { return .strongInterest }

                let ourScore = scoreOfferForMotivation(
                    salary: offer.salary,
                    isPlayerTeam: true,
                    motivation: player.personality.motivation,
                    teamRecord: nil,
                    mediaMarket: nil
                )
                let bestScore = scoreOfferForMotivation(
                    salary: best.salary,
                    isPlayerTeam: false,
                    motivation: player.personality.motivation,
                    teamRecord: nil,
                    mediaMarket: nil
                )

                let ratio = ourScore / max(bestScore, 1)
                if ratio > 1.15 { return .strongInterest }
                if ratio > 0.95 { return .prefersYou }
                if ratio > 0.80 { return .undecided }
                return .leaningAway
            }()

            let isBiddingWar = competingBids.count >= 4

            updates.append(BiddingUpdate(
                playerID: playerID,
                playerName: player.fullName,
                position: player.position.rawValue,
                yourOffer: offer.salary,
                yourYears: offer.years,
                highestCompetingOffer: fuzzedHighest,
                highestCompetingTeam: bestCompeting?.teamAbbr,
                totalBidders: competingBids.count + 1, // +1 for us
                playerLeaning: leaning,
                isBiddingWar: isBiddingWar
            ))
        }

        return updates.sorted { $0.yourOffer > $1.yourOffer }
    }

    /// Score a salary offer based on player motivation (used for leaning calculation).
    private static func scoreOfferForMotivation(
        salary: Int,
        isPlayerTeam: Bool,
        motivation: Motivation,
        teamRecord: (wins: Int, losses: Int)?,
        mediaMarket: MediaMarket?
    ) -> Double {
        var score = Double(salary)

        switch motivation {
        case .money:
            score *= 1.3
        case .winning:
            if isPlayerTeam {
                score *= 1.15
            }
            if let record = teamRecord {
                let winPct = Double(record.wins) / Double(max(record.wins + record.losses, 1))
                score *= (1.0 + winPct * 0.15)
            }
        case .stats:
            score *= 1.05
            if isPlayerTeam { score *= 1.05 }
        case .loyalty:
            score *= isPlayerTeam ? 1.25 : 0.9
        case .fame:
            score *= 1.1
            if let market = mediaMarket {
                score *= market.freeAgentAttraction
            }
        }

        if isPlayerTeam {
            score *= 1.1
        }

        return score
    }

    // MARK: - Player Decision (Enhanced with Motivation)

    struct PlayerDecision {
        let accepted: Bool
        let chosenTeamID: UUID?
        let chosenTeamName: String?
        let reason: String          // ALWAYS populated
        let salary: Int?
        let years: Int?
        let shoppingAround: Bool    // Player doesn't sign yet, wants to see more offers
    }

    /// Determine a free agent's decision given the player's offer and AI bids.
    /// Enhanced with motivation-based preferences and "shopping around" mechanic.
    static func resolvePlayerDecision(
        player: Player,
        playerOffer: (salary: Int, years: Int)?,
        aiBids: [AIBid],
        round: Int,
        allTeams: [Team]? = nil
    ) -> PlayerDecision {
        // Combine player offer with AI bids
        struct Bid {
            let teamID: UUID?
            let teamName: String
            let salary: Int
            let years: Int
            let isPlayer: Bool
            let mediaMarket: MediaMarket?
            let teamRecord: (wins: Int, losses: Int)?
        }

        let teams = allTeams ?? []

        var allBids: [Bid] = aiBids.map { aiBid in
            let teamData = teams.first { $0.id == aiBid.teamID }
            return Bid(
                teamID: aiBid.teamID,
                teamName: aiBid.teamAbbr,
                salary: aiBid.salary,
                years: aiBid.years,
                isPlayer: false,
                mediaMarket: teamData?.mediaMarket,
                teamRecord: teamData.map { (wins: $0.wins, losses: $0.losses) }
            )
        }

        if let offer = playerOffer {
            allBids.append(Bid(
                teamID: nil,
                teamName: "Your Team",
                salary: offer.salary,
                years: offer.years,
                isPlayer: true,
                mediaMarket: nil,
                teamRecord: nil
            ))
        }

        guard !allBids.isEmpty else {
            return PlayerDecision(
                accepted: false,
                chosenTeamID: nil,
                chosenTeamName: nil,
                reason: "No offers received \u{2014} will wait for better opportunities",
                salary: nil,
                years: nil,
                shoppingAround: false
            )
        }

        // Check if player wants to shop around (multiple competitive offers, early rounds)
        if allBids.count >= 2 && round <= 3 {
            let salaries = allBids.map(\.salary).sorted(by: >)
            if salaries.count >= 2 {
                let topOffer = salaries[0]
                let secondOffer = salaries[1]
                // If offers are within 20% of each other, player shops around
                let ratio = Double(secondOffer) / Double(max(topOffer, 1))
                if ratio > 0.80 && round < 3 {
                    // Player doesn't decide yet on rounds 1-2 if offers are competitive
                    let bestBid = allBids.max(by: { $0.salary < $1.salary })!
                    return PlayerDecision(
                        accepted: false,
                        chosenTeamID: bestBid.isPlayer ? nil : bestBid.teamID,
                        chosenTeamName: bestBid.teamName,
                        reason: "Wants to explore all options before committing",
                        salary: bestBid.salary,
                        years: bestBid.years,
                        shoppingAround: true
                    )
                }
            }
        }

        // Score each bid based on player motivation (enhanced)
        func scoreBid(_ bid: Bid) -> Double {
            var score = Double(bid.salary)

            switch player.personality.motivation {
            case .money:
                // Always picks highest offer -- salary is king
                score *= 1.3

            case .winning:
                // Prefers teams with better record (discount up to 15%)
                if let record = bid.teamRecord {
                    let winPct = Double(record.wins) / Double(max(record.wins + record.losses, 1))
                    score *= (1.0 + winPct * 0.15)
                }
                if bid.isPlayer { score *= 1.15 }

            case .stats:
                // Prefers teams where they'll start
                score *= 1.05
                if bid.isPlayer { score *= 1.05 }

            case .loyalty:
                // Prefers current team (discount up to 20%)
                score *= bid.isPlayer ? 1.25 : 0.85

            case .fame:
                // Prefers big-market teams
                if let market = bid.mediaMarket {
                    score *= market.freeAgentAttraction
                }
                score *= 1.1
            }

            // General player-team loyalty bonus
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
                years: best.bid.years,
                shoppingAround: false
            )
        } else {
            return PlayerDecision(
                accepted: false,
                chosenTeamID: best.bid.teamID,
                chosenTeamName: best.bid.teamName,
                reason: playerRejectReason(player: player, chosenTeam: best.bid.teamName, salary: best.bid.salary, playerOffer: playerOffer),
                salary: best.bid.salary,
                years: best.bid.years,
                shoppingAround: false
            )
        }
    }

    // MARK: - Media Headlines

    /// Generate media headlines for a round's signings and rejections.
    static func generateHeadlines(
        signings: [(playerName: String, position: String, team: String, salary: Int)],
        rejections: [(playerName: String, chosenTeam: String?)],
        biddingWars: [BiddingWarInfo] = [],
        playerTeamAbbr: String,
        round: Int
    ) -> [String] {
        var headlines: [String] = []

        // Bidding war headlines (most exciting, show first)
        for war in biddingWars.prefix(2) {
            let templates = [
                "Bidding war erupts for \(war.playerName) -- \(war.bidderCount) teams drive price up!",
                "\(war.playerName) in high demand: \(war.bidderCount)-team bidding war sends price soaring",
                "Frenzy: \(war.position) \(war.playerName) at center of \(war.bidderCount)-team bidding war",
            ]
            headlines.append(templates.randomElement()!)

            if !war.droppedOutTeams.isEmpty {
                let dropped = war.droppedOutTeams.prefix(2).joined(separator: ", ")
                headlines.append("\(dropped) drop\(war.droppedOutTeams.count == 1 ? "s" : "") out of \(war.playerName) sweepstakes")
            }
        }

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
