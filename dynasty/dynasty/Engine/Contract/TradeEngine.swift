import Foundation
import SwiftData

// MARK: - Trade Proposal

struct TradeProposal: Identifiable, Codable {
    let id: UUID
    /// Player UUIDs the user's team is sending away.
    var sendingPlayers: [UUID]
    /// Player UUIDs the user's team is receiving.
    var receivingPlayers: [UUID]
    /// DraftPick UUIDs the user's team is sending away.
    var sendingPicks: [UUID]
    /// DraftPick UUIDs the user's team is receiving.
    var receivingPicks: [UUID]

    /// The team that originated / is offering this proposal.
    var offeringTeamID: UUID
    /// The team on the receiving end of this proposal.
    var receivingTeamID: UUID

    init(
        id: UUID = UUID(),
        offeringTeamID: UUID,
        receivingTeamID: UUID,
        sendingPlayers: [UUID] = [],
        receivingPlayers: [UUID] = [],
        sendingPicks: [UUID] = [],
        receivingPicks: [UUID] = []
    ) {
        self.id = id
        self.offeringTeamID = offeringTeamID
        self.receivingTeamID = receivingTeamID
        self.sendingPlayers = sendingPlayers
        self.receivingPlayers = receivingPlayers
        self.sendingPicks = sendingPicks
        self.receivingPicks = receivingPicks
    }
}

// MARK: - Trade Engine

enum TradeEngine {

    // MARK: - Value Evaluation

    /// Returns the total trade value for each side of the proposal.
    ///
    /// Player value = ContractEngine.estimateMarketValue (overall, age, position, contract).
    /// Pick value   = DraftEngine.pickValue (classic NFL pick chart).
    ///
    /// - Returns: A tuple `(sendingValue, receivingValue)` where "sending" is what
    ///   the **offering** team gives up and "receiving" is what they get back.
    static func evaluateTradeValue(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> (sendingValue: Int, receivingValue: Int) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let sendingValue =
            proposal.sendingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }
            +
            proposal.sendingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + DraftEngine.pickValue($1.pickNumber) }

        let receivingValue =
            proposal.receivingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }
            +
            proposal.receivingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + DraftEngine.pickValue($1.pickNumber) }

        return (sendingValue, receivingValue)
    }

    // MARK: - AI Acceptance Logic

    /// Returns `true` if the AI team would accept the given proposal.
    ///
    /// Acceptance criteria:
    /// - The value coming **into** the AI team must be ≥ 90 % of the value going out
    ///   (slight 10 % buffer so the AI doesn't demand perfection).
    /// - Additionally the AI considers its own positional needs: if the players being
    ///   sent away fill a position the AI is weak at, it is 20 % less likely to trade
    ///   them (reflected as a 20 % premium on their value when evaluating).
    static func aiWouldAccept(
        proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> Bool {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        // From the AI's perspective: "sending" = what AI gives up, "receiving" = what AI gets.
        // In the proposal the AI is the receiving team, so:
        //   AI gives up  → proposal.receivingPlayers / receivingPicks
        //   AI gets      → proposal.sendingPlayers   / sendingPicks

        let aiRoster = allPlayers.filter { $0.teamID == aiTeam.id }
        let needs = evaluateTeamNeeds(roster: aiRoster)

        // Value AI is giving up (adjusted upward for needed positions)
        var aiGiving: Int = 0
        for playerID in proposal.receivingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            var value = ContractEngine.estimateMarketValue(player: player)
            let needMultiplier = needs[player.position] ?? 1.0
            // If this position has a high need (> 1.1) the AI values keeping them more
            if needMultiplier > 1.1 {
                value = Int(Double(value) * 1.2)
            }
            aiGiving += value
        }
        aiGiving += proposal.receivingPicks.compactMap { pickLookup[$0] }
            .reduce(0) { $0 + DraftEngine.pickValue($1.pickNumber) }

        // Value AI is receiving
        var aiGetting: Int = 0
        for playerID in proposal.sendingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            let value = ContractEngine.estimateMarketValue(player: player)
            // Boost value if incoming player fills a position the AI needs
            let needMultiplier = needs[player.position] ?? 1.0
            aiGetting += Int(Double(value) * needMultiplier)
        }
        aiGetting += proposal.sendingPicks.compactMap { pickLookup[$0] }
            .reduce(0) { $0 + DraftEngine.pickValue($1.pickNumber) }

        guard aiGiving > 0 else {
            // AI is giving up nothing; always accept free assets
            return true
        }

        // Accept if receiving value is at least 90 % of giving value
        return Double(aiGetting) >= Double(aiGiving) * 0.9
    }

    // MARK: - AI Offer Generation

    /// Generates 0–3 incoming trade proposals from random AI teams targeting the
    /// user's team each week.
    ///
    /// AI teams will:
    /// 1. Identify good players on the user's team that they need.
    /// 2. Build a return package of their own players / picks that roughly matches value.
    /// 3. Only offer if the package can cover at least 85 % of the target's value.
    static func generateAITradeOffers(
        forTeam playerTeam: Team,
        allTeams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> [TradeProposal] {
        guard !playerTeam.players.isEmpty else { return [] }

        let aiTeams = allTeams.filter { $0.id != playerTeam.id }
        var proposals: [TradeProposal] = []

        // How many offers to generate this week (0-3)
        let offerCount = Int.random(in: 0...3)
        guard offerCount > 0 else { return [] }

        var shuffledAI = aiTeams.shuffled()

        for aiTeam in shuffledAI.prefix(offerCount * 2) {
            guard proposals.count < offerCount else { break }

            let aiRoster   = allPlayers.filter { $0.teamID == aiTeam.id }
            let aiNeeds    = evaluateTeamNeeds(roster: aiRoster)
            let aiPicks    = allPicks.filter { $0.currentTeamID == aiTeam.id && !$0.isComplete }
            let userPicks  = allPicks.filter { $0.currentTeamID == playerTeam.id && !$0.isComplete }

            // Sort user's players by market value descending; pick one the AI wants
            let userPlayers = allPlayers.filter { $0.teamID == playerTeam.id }
            let targets = userPlayers
                .sorted {
                    ContractEngine.estimateMarketValue(player: $0) >
                    ContractEngine.estimateMarketValue(player: $1)
                }
                .filter { player in
                    // AI wants the player if it has a positional need there
                    let need = aiNeeds[player.position] ?? 1.0
                    return need > 1.0 && player.overall >= 65
                }
                .prefix(5)

            guard let target = targets.randomElement() else { continue }

            let targetValue = ContractEngine.estimateMarketValue(player: target)

            // Build AI return package: try to match target value with players + picks
            var packagePlayers: [UUID] = []
            var packagePicks:   [UUID] = []
            var packageValue = 0

            // First try matching with AI players the user might want
            let aiPlayersSorted = aiRoster
                .filter { $0.overall >= 60 }
                .sorted { $0.overall > $1.overall }

            for player in aiPlayersSorted {
                guard packageValue < targetValue else { break }
                packagePlayers.append(player.id)
                packageValue += ContractEngine.estimateMarketValue(player: player)
            }

            // Fill remaining gap with picks if needed
            if packageValue < targetValue {
                let sortedPicks = aiPicks.sorted { $0.pickNumber < $1.pickNumber }
                for pick in sortedPicks {
                    guard packageValue < targetValue else { break }
                    packagePicks.append(pick.id)
                    packageValue += DraftEngine.pickValue(pick.pickNumber)
                }
            }

            // Only proceed if package reaches 85 % of target value
            guard Double(packageValue) >= Double(targetValue) * 0.85 else { continue }

            // Random chance: not every AI team submits an offer even if eligible
            guard Int.random(in: 1...100) <= 40 else { continue }

            let proposal = TradeProposal(
                offeringTeamID: aiTeam.id,
                receivingTeamID: playerTeam.id,
                sendingPlayers: packagePlayers,
                receivingPlayers: [target.id],
                sendingPicks: packagePicks,
                receivingPicks: []
            )
            proposals.append(proposal)
        }

        return proposals
    }

    // MARK: - Execute Trade

    /// Applies a trade proposal to the data store:
    /// - Swaps `teamID` on each player.
    /// - Swaps `currentTeamID` on each draft pick.
    /// - Updates `currentCapUsage` on both teams.
    static func executeTrade(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick],
        modelContext: ModelContext
    ) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        // Fetch both teams
        let offeringTeamID  = proposal.offeringTeamID
        let receivingTeamID = proposal.receivingTeamID

        let teamDescriptor = FetchDescriptor<Team>()
        let allTeams = (try? modelContext.fetch(teamDescriptor)) ?? []
        let teamLookup = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        guard let offeringTeam  = teamLookup[offeringTeamID],
              let receivingTeam = teamLookup[receivingTeamID]
        else { return }

        // --- Move sending players: offering → receiving ---
        for playerID in proposal.sendingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            let salary = player.annualSalary
            offeringTeam.currentCapUsage  -= salary
            receivingTeam.currentCapUsage += salary
            player.teamID = receivingTeamID
        }

        // --- Move receiving players: receiving → offering ---
        for playerID in proposal.receivingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            let salary = player.annualSalary
            receivingTeam.currentCapUsage -= salary
            offeringTeam.currentCapUsage  += salary
            player.teamID = offeringTeamID
        }

        // --- Move sending picks: offering → receiving ---
        for pickID in proposal.sendingPicks {
            guard let pick = pickLookup[pickID] else { continue }
            pick.currentTeamID = receivingTeamID
        }

        // --- Move receiving picks: receiving → offering ---
        for pickID in proposal.receivingPicks {
            guard let pick = pickLookup[pickID] else { continue }
            pick.currentTeamID = offeringTeamID
        }
    }

    // MARK: - Private Helpers

    /// Mirrors the need-evaluation logic from DraftEngine so TradeEngine remains
    /// independent and does not break the compilation boundary.
    private static func evaluateTeamNeeds(roster: [Player]) -> [Position: Double] {
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2,
            .K: 1, .P: 1
        ]

        var currentCounts: [Position: Int] = [:]
        var positionOveralls: [Position: [Int]] = [:]
        for player in roster {
            currentCounts[player.position, default: 0] += 1
            positionOveralls[player.position, default: []].append(player.overall)
        }

        var needs: [Position: Double] = [:]
        for position in Position.allCases {
            let ideal   = idealCounts[position] ?? 1
            let current = currentCounts[position] ?? 0
            let deficit = max(0, ideal - current)

            var multiplier = 1.0 + Double(deficit) * 0.15

            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += 0.2
                } else if avgOverall < 70.0 {
                    multiplier += 0.1
                }
            } else {
                multiplier += 0.3
            }

            needs[position] = multiplier
        }

        return needs
    }
}
