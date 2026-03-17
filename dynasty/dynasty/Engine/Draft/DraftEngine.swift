import Foundation

/// Stateless engine that handles all NFL Draft logic: order generation,
/// AI pick selection, prospect-to-player conversion, pick value chart,
/// and trade evaluation.
enum DraftEngine {

    // MARK: - Draft Setup

    /// Generates the full 7-round, 224-pick draft order based on reverse standings.
    ///
    /// - Playoff teams pick later in each round.
    /// - The Super Bowl loser picks 31st; the Super Bowl winner picks 32nd.
    ///
    /// - Parameters:
    ///   - teams: All 32 teams in the league.
    ///   - games: All games for the season (used to derive standings and playoff results).
    ///   - seasonYear: The year of the draft.
    /// - Returns: An array of 224 `DraftPick` objects ordered by overall pick number.
    static func generateDraftOrder(teams: [Team], games: [Game], seasonYear: Int) -> [DraftPick] {
        let records = StandingsCalculator.calculate(games: games, teams: teams)

        // Determine playoff teams for each conference (top 7 seeds).
        let afcPlayoff = StandingsCalculator.playoffTeams(
            records: records, teams: teams, conference: .AFC
        )
        let nfcPlayoff = StandingsCalculator.playoffTeams(
            records: records, teams: teams, conference: .NFC
        )
        let playoffTeamIDs = Set((afcPlayoff + nfcPlayoff).map(\.teamID))

        // Identify the Super Bowl participants from playoff games.
        // The championship game is the last played playoff game of the season.
        let playoffGames = games
            .filter { $0.isPlayoff && $0.isPlayed }
            .sorted { $0.week < $1.week }

        let superBowlWinnerID = playoffGames.last?.winnerID
        let superBowlLoserID = playoffGames.last?.loserID

        // Split teams into non-playoff and playoff groups.
        var nonPlayoffRecords = records.filter { !playoffTeamIDs.contains($0.teamID) }
        var playoffRecords = records.filter {
            playoffTeamIDs.contains($0.teamID)
            && $0.teamID != superBowlWinnerID
            && $0.teamID != superBowlLoserID
        }

        // Sort non-playoff teams worst-to-best (worst record picks first).
        nonPlayoffRecords.sort { worstFirst($0, $1) }

        // Sort playoff teams worst-to-best among those eliminated before the Super Bowl.
        playoffRecords.sort { worstFirst($0, $1) }

        // Build the pick order: non-playoff (worst first), then playoff losers,
        // then Super Bowl loser, then Super Bowl winner.
        var orderedTeamIDs: [UUID] = nonPlayoffRecords.map(\.teamID)
            + playoffRecords.map(\.teamID)

        if let loserID = superBowlLoserID {
            orderedTeamIDs.append(loserID)
        }
        if let winnerID = superBowlWinnerID {
            orderedTeamIDs.append(winnerID)
        }

        // Ensure we have exactly 32 teams. If Super Bowl IDs could not be determined
        // (e.g., no playoff games yet), fall back to pure reverse standings.
        if orderedTeamIDs.count != 32 {
            var fallback = records
            fallback.sort { worstFirst($0, $1) }
            orderedTeamIDs = fallback.map(\.teamID)
        }

        // Generate 7 rounds of 32 picks each.
        var picks: [DraftPick] = []
        for round in 1...7 {
            for (index, teamID) in orderedTeamIDs.enumerated() {
                let overall = (round - 1) * 32 + (index + 1)
                let pick = DraftPick(
                    seasonYear: seasonYear,
                    round: round,
                    pickNumber: overall,
                    originalTeamID: teamID,
                    currentTeamID: teamID
                )
                picks.append(pick)
            }
        }

        return picks
    }

    // MARK: - AI Draft Logic

    /// AI selects the best prospect for a given team based on roster needs
    /// and prospect quality.
    ///
    /// - Parameters:
    ///   - team: The team making the pick.
    ///   - availableProspects: Prospects still on the board.
    ///   - teamRoster: Current players on the team's roster.
    /// - Returns: The prospect the AI selects.
    static func aiMakePick(
        team: Team,
        availableProspects: [CollegeProspect],
        teamRoster: [Player]
    ) -> CollegeProspect {
        guard !availableProspects.isEmpty else {
            fatalError("aiMakePick called with no available prospects")
        }

        let needs = evaluateTeamNeeds(roster: teamRoster)

        // Score each prospect: combination of true overall talent and positional need.
        let scored = availableProspects.map { prospect -> (CollegeProspect, Double) in
            var score = Double(prospect.trueOverall)

            // Boost score for positions the team needs.
            let needMultiplier = needs[prospect.position] ?? 1.0
            score *= needMultiplier

            // QB premium: if team needs a QB, boost significantly.
            if prospect.position == .QB && (needs[.QB] ?? 1.0) > 1.2 {
                score *= 1.15
            }

            // Factor in potential (prospects with higher ceilings are more attractive).
            score += Double(prospect.truePotential) * 0.15

            // Slight bonus for prospects projected to go in this range (consensus value).
            if let projection = prospect.draftProjection, projection > 0 {
                // Lower projection number = better prospect. Give a small bump.
                let projectionBonus = max(0.0, Double(100 - projection) * 0.05)
                score += projectionBonus
            }

            return (prospect, score)
        }

        // Return the highest-scored prospect.
        let best = scored.max(by: { $0.1 < $1.1 })!
        return best.0
    }

    // MARK: - Convert Prospect to Player

    /// Creates a `Player` from a drafted `CollegeProspect` using the prospect's true
    /// (not scouted) attributes. Rookie contract terms are based on pick number.
    ///
    /// - Parameters:
    ///   - prospect: The college prospect being drafted.
    ///   - teamID: The UUID of the team drafting the player.
    ///   - pickNumber: The overall draft pick number (1-224).
    /// - Returns: A fully initialized `Player` ready to be inserted into the data store.
    static func convertToPlayer(
        prospect: CollegeProspect,
        teamID: UUID,
        pickNumber: Int
    ) -> Player {
        let contract = rookieContract(pickNumber: pickNumber)

        return Player(
            firstName: prospect.firstName,
            lastName: prospect.lastName,
            position: prospect.position,
            age: prospect.age,
            yearsPro: 0,
            physical: prospect.truePhysical,
            mental: prospect.trueMental,
            positionAttributes: prospect.truePositionAttributes,
            personality: prospect.truePersonality,
            truePotential: prospect.truePotential,
            teamID: teamID,
            contractYearsRemaining: contract.years,
            annualSalary: contract.salary
        )
    }

    // MARK: - Pick Value Chart

    /// Returns the trade value of a draft pick using a classic NFL-style value chart.
    ///
    /// - Pick 1 = 3000, Pick 32 ~= 590, Pick 224 = 2.
    /// - Values decrease steeply in early rounds and flatten in later rounds.
    ///
    /// - Parameter pickNumber: Overall pick number (1-224).
    /// - Returns: Integer value for trade evaluation purposes.
    static func pickValue(_ pickNumber: Int) -> Int {
        guard pickNumber >= 1 && pickNumber <= 224 else { return 0 }

        // Classic NFL Draft Trade Value Chart (simplified piecewise curve).
        // First round (1-32): steep decline from 3000.
        // Second round (33-64): moderate decline.
        // Rounds 3-7 (65-224): gradual decline to near-minimum.
        if pickNumber <= 32 {
            return firstRoundValue(pickNumber)
        } else if pickNumber <= 64 {
            return secondRoundValue(pickNumber)
        } else {
            return laterRoundValue(pickNumber)
        }
    }

    // MARK: - Trade Evaluation

    /// Evaluates a trade offer by comparing the total pick value on each side.
    ///
    /// - Parameters:
    ///   - offer: The trade offer to evaluate.
    ///   - picks: All draft picks (used to look up pick numbers for value calculation).
    /// - Returns: A ratio where > 1.0 means the offering team is overpaying
    ///   (good deal for the receiving team), and < 1.0 means the receiving team
    ///   would be overpaying (bad deal for receiver).
    static func evaluateTradeOffer(offer: TradeOffer, picks: [DraftPick]) -> Double {
        let pickLookup = Dictionary(uniqueKeysWithValues: picks.map { ($0.id, $0) })

        // Value the offering team is sending.
        let sendingPickValue = offer.picksSending.compactMap { pickLookup[$0] }
            .reduce(0) { $0 + pickValue($1.pickNumber) }

        // Value the offering team is receiving.
        let receivingPickValue = offer.picksReceiving.compactMap { pickLookup[$0] }
            .reduce(0) { $0 + pickValue($1.pickNumber) }

        // Player trades add a flat value (approximate; a more sophisticated engine
        // could factor in player overall rating and contract).
        let sendingPlayerValue = offer.playersSending.count * 200
        let receivingPlayerValue = offer.playersReceiving.count * 200

        let totalSending = Double(sendingPickValue + sendingPlayerValue)
        let totalReceiving = Double(receivingPickValue + receivingPlayerValue)

        guard totalReceiving > 0 else { return 0.0 }

        return totalSending / totalReceiving
    }

    // MARK: - AI Trade Offers

    /// Generates 0-3 trade-up offers from AI teams for the current pick.
    ///
    /// AI teams that want to move up will offer a package of their own picks
    /// in exchange for the current pick.
    ///
    /// - Parameters:
    ///   - currentPick: The pick currently on the clock.
    ///   - allPicks: All draft picks for the current draft.
    ///   - teams: All teams in the league.
    /// - Returns: An array of trade offers (may be empty if no team wants to trade up).
    static func generateAITradeOffers(
        currentPick: DraftPick,
        allPicks: [DraftPick],
        teams: [Team]
    ) -> [TradeOffer] {
        let currentValue = pickValue(currentPick.pickNumber)

        // Only generate trade-up offers for picks with meaningful value.
        guard currentValue >= 100 else { return [] }

        // Find teams that pick later and might want to trade up.
        let remainingPicks = allPicks.filter { !$0.isComplete && $0.id != currentPick.id }
        let teamPicksMap = Dictionary(grouping: remainingPicks) { $0.currentTeamID }

        var offers: [TradeOffer] = []

        for (teamID, teamPicks) in teamPicksMap {
            // Skip the team that already owns this pick.
            guard teamID != currentPick.currentTeamID else { continue }

            // Only consider teams with picks after the current one.
            let laterPicks = teamPicks
                .filter { $0.pickNumber > currentPick.pickNumber }
                .sorted { $0.pickNumber < $1.pickNumber }

            guard !laterPicks.isEmpty else { continue }

            // Try to build a package that roughly matches the current pick's value.
            var packagePicks: [DraftPick] = []
            var packageValue = 0

            for pick in laterPicks {
                packagePicks.append(pick)
                packageValue += pickValue(pick.pickNumber)

                // Offer is viable if the package value is at least 85% of the target.
                if Double(packageValue) >= Double(currentValue) * 0.85 {
                    break
                }
            }

            // Only offer if the package is within a reasonable range (85%-130%).
            let ratio = Double(packageValue) / Double(currentValue)
            guard ratio >= 0.85 && ratio <= 1.30 else { continue }

            // Random chance: not every eligible team actually wants to trade up.
            guard Int.random(in: 1...100) <= 25 else { continue }

            let offer = TradeOffer(
                offeringTeamID: teamID,
                receivingTeamID: currentPick.currentTeamID,
                picksSending: packagePicks.map(\.id),
                picksReceiving: [currentPick.id]
            )
            offers.append(offer)

            // Cap at 3 offers.
            if offers.count >= 3 { break }
        }

        return offers
    }

    // MARK: - Private Helpers

    /// Sorts records so the worst team comes first (lowest win percentage).
    private static func worstFirst(_ lhs: StandingsRecord, _ rhs: StandingsRecord) -> Bool {
        if lhs.winPercentage != rhs.winPercentage {
            return lhs.winPercentage < rhs.winPercentage
        }
        // Tiebreaker: worse point differential picks earlier.
        return lhs.pointDifferential < rhs.pointDifferential
    }

    /// Evaluates which positions a team needs most.
    /// Returns a dictionary of position -> multiplier (> 1.0 means higher need).
    private static func evaluateTeamNeeds(roster: [Player]) -> [Position: Double] {
        // Ideal roster composition targets (starters per position).
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2,
            .K: 1, .P: 1
        ]

        // Count current roster players by position.
        var currentCounts: [Position: Int] = [:]
        for player in roster {
            currentCounts[player.position, default: 0] += 1
        }

        // Calculate average overall by position to detect quality gaps.
        var positionOveralls: [Position: [Int]] = [:]
        for player in roster {
            positionOveralls[player.position, default: []].append(player.overall)
        }

        var needs: [Position: Double] = [:]
        for position in Position.allCases {
            let ideal = idealCounts[position] ?? 1
            let current = currentCounts[position] ?? 0
            let deficit = max(0, ideal - current)

            // Base multiplier: higher deficit = higher need.
            var multiplier = 1.0 + Double(deficit) * 0.15

            // If the team has players at this position but they are low-rated, boost need.
            if let overalls = positionOveralls[position], !overalls.isEmpty {
                let avgOverall = Double(overalls.reduce(0, +)) / Double(overalls.count)
                if avgOverall < 60.0 {
                    multiplier += 0.2
                } else if avgOverall < 70.0 {
                    multiplier += 0.1
                }
            } else {
                // No players at all at this position — significant need.
                multiplier += 0.3
            }

            needs[position] = multiplier
        }

        return needs
    }

    /// Determines rookie contract years and salary based on draft pick number.
    /// - 1st round: 4 years, salary scaled by pick position.
    /// - 2nd round: 4 years, lower salary.
    /// - 3rd-4th round: 4 years, modest salary.
    /// - 5th-7th round: 3 years, league minimum-tier salary.
    private static func rookieContract(pickNumber: Int) -> (years: Int, salary: Int) {
        switch pickNumber {
        case 1:
            return (years: 4, salary: 40_000)   // ~$40M/yr for #1 overall
        case 2...5:
            return (years: 4, salary: 30_000)   // ~$30M/yr
        case 6...10:
            return (years: 4, salary: 20_000)   // ~$20M/yr
        case 11...16:
            return (years: 4, salary: 14_000)   // ~$14M/yr
        case 17...32:
            return (years: 4, salary: 10_000)   // ~$10M/yr
        case 33...64:
            return (years: 4, salary: 5_000)    // ~$5M/yr (2nd round)
        case 65...100:
            return (years: 4, salary: 2_500)    // ~$2.5M/yr (3rd round)
        case 101...128:
            return (years: 4, salary: 1_500)    // ~$1.5M/yr (4th round)
        case 129...160:
            return (years: 3, salary: 1_000)    // ~$1M/yr (5th round)
        case 161...192:
            return (years: 3, salary: 900)      // ~$900K/yr (6th round)
        default:
            return (years: 3, salary: 750)      // ~$750K/yr (7th round)
        }
    }

    // MARK: - Pick Value Chart Internals

    /// First round pick values (1-32). Steep decline.
    private static func firstRoundValue(_ pick: Int) -> Int {
        // Piecewise linear approximation of the classic Jimmy Johnson chart.
        let values: [Int: Int] = [
            1: 3000, 2: 2600, 3: 2200, 4: 1800, 5: 1700,
            6: 1600, 7: 1500, 8: 1400, 9: 1350, 10: 1300,
            11: 1250, 12: 1200, 13: 1150, 14: 1100, 15: 1050,
            16: 1000, 17: 950, 18: 900, 19: 875, 20: 850,
            21: 800, 22: 780, 23: 760, 24: 740, 25: 720,
            26: 700, 27: 680, 28: 660, 29: 640, 30: 620,
            31: 600, 32: 590
        ]
        return values[pick] ?? 590
    }

    /// Second round pick values (33-64). Moderate decline.
    private static func secondRoundValue(_ pick: Int) -> Int {
        // Linearly interpolate from ~580 down to ~270.
        let start = 580.0
        let end = 270.0
        let progress = Double(pick - 33) / 31.0
        return Int(start - (start - end) * progress)
    }

    /// Rounds 3-7 pick values (65-224). Gradual decline to near-minimum.
    private static func laterRoundValue(_ pick: Int) -> Int {
        // Linearly interpolate from ~260 down to 2.
        let start = 260.0
        let end = 2.0
        let progress = Double(pick - 65) / 159.0
        return max(2, Int(start - (start - end) * progress))
    }
}
