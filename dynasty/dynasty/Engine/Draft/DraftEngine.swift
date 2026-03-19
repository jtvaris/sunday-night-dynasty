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

    // MARK: - Media Commentary

    /// Generates a media grade, headline, and comment for a draft pick.
    ///
    /// Compares the prospect's projected round against the actual pick to determine
    /// whether the pick is a reach, solid, or great value. Need-match boosts the grade.
    ///
    /// - Parameters:
    ///   - prospect: The college prospect who was drafted.
    ///   - pickNumber: The overall pick number (1-224).
    ///   - teamNeeds: Positions the drafting team needs most.
    /// - Returns: A tuple of (grade, headline, comment).
    static func generateMediaGrade(
        prospect: CollegeProspect,
        pickNumber: Int,
        teamNeeds: [Position]
    ) -> (grade: String, headline: String, comment: String) {
        let gradeScale = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]

        // Determine the actual round from pick number.
        let actualRound = ((pickNumber - 1) / 32) + 1

        // Determine the projected round (draftProjection is a round number, e.g. 1, 2, 3...).
        let projectedRound = prospect.draftProjection ?? actualRound

        // Base grade index: start at B (index 4).
        var gradeIndex = 4

        // Compare projected vs actual round.
        let roundDelta = actualRound - projectedRound
        // Negative delta = picked earlier than projected (reach), positive = picked later (value).

        if roundDelta < -1 {
            gradeIndex += 3 // Major reach: C- or worse
        } else if roundDelta == -1 {
            gradeIndex += 2 // Moderate reach: C+
        } else if roundDelta == 0 {
            gradeIndex -= 1 // Solid pick: B+
        } else if roundDelta == 1 {
            gradeIndex -= 2 // Good value: A-
        } else {
            gradeIndex -= 3 // Great value: A or A+
        }

        // Need match bonus: picking a position of need = +1 grade (lower index).
        if teamNeeds.contains(prospect.position) {
            gradeIndex -= 1
        }

        // High-talent bonus: if true overall >= 80, slight boost.
        if prospect.trueOverall >= 80 {
            gradeIndex -= 1
        }

        // Clamp to valid range.
        gradeIndex = max(0, min(gradeScale.count - 1, gradeIndex))
        let grade = gradeScale[gradeIndex]

        // Generate headline and comment.
        let teamAbbr = prospect.mockDraftTeam ?? "Team"
        let name = prospect.lastName
        let pos = prospect.position.rawValue
        let roundLabel = roundName(actualRound)

        let headline: String
        let comment: String

        if roundDelta >= 2 {
            // Great value
            let headlines = [
                "\(name) falls to \(roundLabel) — steal!",
                "Incredible value: \(name) in \(roundLabel)!",
                "\(pos) \(name) is a draft-day steal!"
            ]
            headline = headlines[pickNumber % headlines.count]
            let comments = [
                "\(prospect.fullName) was projected to go much earlier. This is a tremendous value pick that could pay dividends for years.",
                "How did \(prospect.fullName) fall this far? A gift for the franchise that just landed a potential star at \(pos)."
            ]
            comment = comments[pickNumber % comments.count]
        } else if roundDelta == 1 {
            let headlines = [
                "Nice value on \(name) in \(roundLabel)",
                "\(name) slides just enough — solid get"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) was expected to go a round earlier. Getting a player of this caliber at pick \(pickNumber) is smart drafting."
        } else if roundDelta == 0 {
            let headlines = [
                "\(name) goes right where expected",
                "No surprises: \(pos) \(name) at pick \(pickNumber)"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) lands right at his projected slot. A consensus pick that fills a roster need."
        } else if roundDelta == -1 {
            let headlines = [
                "Slight reach for \(name) at \(pickNumber)",
                "\(name) picked a bit early?"
            ]
            headline = headlines[pickNumber % headlines.count]
            comment = "\(prospect.fullName) was projected to go in the next round. A bit of a reach, but the talent is there if the coaching staff can develop him."
        } else {
            // Major reach
            let headlines = [
                "Surprising reach for \(name) at \(pickNumber)!",
                "Eyebrows raised: \(name) goes early",
                "Bold pick: \(pos) \(name) at \(pickNumber)"
            ]
            headline = headlines[pickNumber % headlines.count]
            let comments = [
                "\(prospect.fullName) was not expected to go this early. The front office must see something the rest of us don't.",
                "This is a head-scratcher. \(prospect.fullName) was projected much later. A risky move that needs to pan out."
            ]
            comment = comments[pickNumber % comments.count]
        }

        return (grade: grade, headline: headline, comment: comment)
    }

    // MARK: - Staff Recommendations

    /// A single coaching staff recommendation for a draft pick.
    struct StaffRecommendation: Identifiable {
        let id = UUID()
        let staffTitle: String
        let message: String
        let prospectID: UUID
        let icon: String
        /// Detailed reasoning explaining why this prospect is recommended.
        var reason: String = ""
    }

    /// Generates 2-3 coaching staff recommendations based on team needs and available prospects.
    ///
    /// - Parameters:
    ///   - availableProspects: Prospects still on the board.
    ///   - teamNeeds: Positions the team needs most (sorted by priority).
    ///   - coaches: The team's coaching staff.
    /// - Returns: An array of 2-3 staff recommendations.
    static func generateStaffRecommendations(
        availableProspects: [CollegeProspect],
        teamNeeds: [Position],
        coaches: [Coach]
    ) -> [StaffRecommendation] {
        guard !availableProspects.isEmpty else { return [] }

        var recommendations: [StaffRecommendation] = []

        // Find the OC's recommendation (offensive need).
        let offensivePositions: Set<Position> = [.QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT]
        let offensiveNeeds = teamNeeds.filter { offensivePositions.contains($0) }
        let bestOffensive = availableProspects
            .filter { offensivePositions.contains($0.position) }
            .sorted { ($0.scoutedOverall ?? $0.trueOverall) > ($1.scoutedOverall ?? $1.trueOverall) }
            .first

        if let prospect = bestOffensive {
            let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
            let title = oc.map { "\($0.lastName), OC" } ?? "Offensive Coordinator"
            let needsMatch = offensiveNeeds.contains(prospect.position)
            let message: String
            let reason: String
            let schemeName = oc?.offensiveScheme.map { "\($0)" } ?? "our offense"
            if needsMatch {
                message = "We need to address \(prospect.position.rawValue). \(prospect.fullName) is the best available and fills a real gap."
                let posGrade = gradeForPositionGroup(prospect.position, needs: teamNeeds)
                reason = "Your \(prospect.position.rawValue) corps is weak (\(posGrade) grade). \(prospect.fullName) fits \(schemeName) and can start Day 1."
            } else {
                message = "\(prospect.fullName) is the best offensive talent on the board. Too good to pass up at \(prospect.position.rawValue)."
                reason = "\(prospect.fullName) is a premium talent at \(prospect.position.rawValue). Even without an immediate need, this caliber of player elevates \(schemeName)."
            }
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "sportscourt.fill",
                reason: reason
            ))
        }

        // Find the DC's recommendation (defensive need).
        let defensivePositions: Set<Position> = [.DE, .DT, .OLB, .MLB, .CB, .FS, .SS]
        let defensiveNeeds = teamNeeds.filter { defensivePositions.contains($0) }
        let bestDefensive = availableProspects
            .filter { defensivePositions.contains($0.position) }
            .sorted { ($0.scoutedOverall ?? $0.trueOverall) > ($1.scoutedOverall ?? $1.trueOverall) }
            .first

        if let prospect = bestDefensive, prospect.id != bestOffensive?.id {
            let dc = coaches.first(where: { $0.role == .defensiveCoordinator })
            let title = dc.map { "\($0.lastName), DC" } ?? "Defensive Coordinator"
            let needsMatch = defensiveNeeds.contains(prospect.position)
            let message: String
            let reason: String
            if needsMatch {
                message = "There's a talented \(prospect.position.rawValue) still on the board. \(prospect.fullName) can transform our defense."
                let isPassRusher = prospect.position == .DE || prospect.position == .OLB
                if isPassRusher {
                    reason = "Pass rush is your biggest defensive need. \(prospect.fullName) projects as an immediate edge threat in our scheme."
                } else {
                    let posGrade = gradeForPositionGroup(prospect.position, needs: teamNeeds)
                    reason = "Your \(prospect.position.rawValue) group grades out at \(posGrade). \(prospect.fullName) fills a critical gap and can compete for a starting role."
                }
            } else {
                message = "\(prospect.fullName) is an elite \(prospect.position.rawValue) prospect. He'd be an instant impact player on this defense."
                reason = "\(prospect.fullName) is too talented to pass up. Best defensive player on the board regardless of need."
            }
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "shield.fill",
                reason: reason
            ))
        }

        // Chief Scout's sleeper pick: highest potential prospect that isn't already recommended.
        let alreadyRecommended = Set(recommendations.map(\.prospectID))
        let sleeperPick = availableProspects
            .filter { !alreadyRecommended.contains($0.id) }
            .sorted { $0.truePotential > $1.truePotential }
            .first

        if let prospect = sleeperPick {
            let scoutName = coaches.first(where: { $0.role == .headCoach })
            let title = scoutName.map { "Scout (\($0.lastName)'s staff)" } ?? "Chief Scout"
            let message = "\(prospect.fullName) is my sleeper pick. Our scouts had him rated higher than the public boards. He's got serious upside at \(prospect.position.rawValue)."
            let reason = "\(prospect.fullName) is my sleeper. His combine numbers don't match his tape \u{2014} he plays faster than he tests. Potential ceiling is elite."
            recommendations.append(StaffRecommendation(
                staffTitle: title,
                message: message,
                prospectID: prospect.id,
                icon: "binoculars.fill",
                reason: reason
            ))
        }

        return recommendations
    }

    /// Returns the top team need positions sorted by priority (highest need first).
    static func topTeamNeeds(roster: [Player], limit: Int = 5) -> [Position] {
        let needs = evaluateTeamNeeds(roster: roster)
        return needs.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
    }

    // MARK: - Trade Value Helpers

    /// NFL-style trade value chart (simplified).
    /// Uses the piecewise `pickValue(_:)` internally.
    static func tradeValue(forPick pickNumber: Int) -> Int {
        pickValue(pickNumber)
    }

    /// Evaluate if a trade is fair (within 15% of equal value).
    ///
    /// - Parameters:
    ///   - offering: Pick numbers the offering side is sending.
    ///   - receiving: Pick numbers the receiving side is sending.
    /// - Returns: Total value for each side and whether the trade is within 15%.
    static func evaluateTradeValue(
        offering: [Int],
        receiving: [Int]
    ) -> (offerValue: Int, receiveValue: Int, isFair: Bool) {
        let offerValue = offering.reduce(0) { $0 + pickValue($1) }
        let receiveValue = receiving.reduce(0) { $0 + pickValue($1) }
        let maxVal = max(offerValue, receiveValue, 1)
        let diff = abs(offerValue - receiveValue)
        let isFair = Double(diff) / Double(maxVal) <= 0.15
        return (offerValue: offerValue, receiveValue: receiveValue, isFair: isFair)
    }

    // MARK: - Fan Reactions / Social Media

    /// Generates 3-5 social media style fan reactions for a draft pick.
    ///
    /// - Parameters:
    ///   - prospect: The college prospect who was drafted.
    ///   - pickNumber: The overall pick number (1-224).
    ///   - teamNeeds: Positions the drafting team needs most.
    ///   - gmName: The player's GM name (for personalized tweets).
    /// - Returns: An array of 3-5 fan reaction strings.
    static func generateFanReaction(
        prospect: CollegeProspect,
        pickNumber: Int,
        teamNeeds: [Position],
        gmName: String = "GM"
    ) -> [String] {
        let actualRound = ((pickNumber - 1) / 32) + 1
        let projectedRound = prospect.draftProjection ?? actualRound
        let roundDelta = actualRound - projectedRound
        let needsMatch = teamNeeds.contains(prospect.position)
        let pos = prospect.position.rawValue
        let name = prospect.lastName

        var pool: [String] = []

        // Great value + fills a need
        if roundDelta >= 1 && needsMatch {
            pool.append("LETS GOOO! Perfect pick! \u{1F525}")
            pool.append("Steal of the draft! \(name) at \(pos)! \u{1F4AA}")
            pool.append("I literally screamed. \(name) was my #1 choice \u{1F389}")
        }

        // Good value pick
        if roundDelta >= 1 {
            pool.append("How did \(name) fall to us?? Christmas came early \u{1F381}")
            pool.append("Great value. \(name) is gonna be a problem \u{1F60F}")
        }

        // Fills a need
        if needsMatch {
            pool.append("Finally addressing \(pos)! About time \u{1F64F}")
            pool.append("We NEEDED a \(pos) so badly. Smart pick \u{2705}")
        }

        // Reach pick
        if roundDelta < -1 {
            pool.append("Who?? Never heard of this guy \u{1F610}")
            pool.append("This is a REACH. Could've gotten him way later \u{1F926}")
            pool.append("I'm gonna be sick. What are we doing?? \u{1F922}")
        }

        // Moderate reach
        if roundDelta == -1 {
            pool.append("Hmm, bit of a reach but I trust the process \u{1F914}")
            pool.append("Slight reach imo but let's see \u{1F440}")
        }

        // Neutral / trust the GM
        pool.append("In \(gmName) we trust \u{1F4AA}")
        pool.append("Welcome to the squad \(name)! \u{1F3C8}")

        // QB-specific reactions
        if prospect.position == .QB {
            if needsMatch {
                pool.append("FRANCHISE QB!! \u{1F451}")
            } else {
                pool.append("Another QB? What about the defense?? \u{1F620}")
            }
        }

        // Missed opportunity reactions (if QB was a need but they didn't draft one)
        if teamNeeds.first == .QB && prospect.position != .QB {
            pool.append("Trade up for a QB! Why didn't we!? \u{1F624}")
            pool.append("So we're just gonna ignore the QB situation huh \u{1F644}")
        }

        // Pick 3-5 unique reactions
        pool.shuffle()
        let count = min(pool.count, Int.random(in: 3...5))
        return Array(pool.prefix(count))
    }

    // MARK: - Private Helpers

    /// Returns a letter grade for a position group based on how high the need is.
    private static func gradeForPositionGroup(_ position: Position, needs: [Position]) -> String {
        guard let index = needs.firstIndex(of: position) else { return "B" }
        switch index {
        case 0: return "D"
        case 1: return "C-"
        case 2: return "C"
        case 3: return "C+"
        default: return "B-"
        }
    }

    /// Returns a human-readable round name.
    private static func roundName(_ round: Int) -> String {
        switch round {
        case 1: return "Round 1"
        case 2: return "Round 2"
        case 3: return "Round 3"
        case 4: return "Round 4"
        case 5: return "Round 5"
        case 6: return "Round 6"
        case 7: return "Round 7"
        default: return "Round \(round)"
        }
    }

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
