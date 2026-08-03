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
        /// The number below which his agent stops negotiating
        /// (`ContractDemand.floorAmount`). An AI signing that ignored this was
        /// the other half of "the AI and the user are on different markets":
        /// clubs settled at `ask × random(0.85…1.0)` with no floor under it at
        /// all, while the user could not get below the agent's floor.
        let floorPrice: Int
        /// Preferred contract length in years.
        let desiredYears: Int
        /// How many teams are interested (1-10 scale). Higher means bidding war.
        let marketInterest: Int
    }

    // MARK: - Signing Ledger (task #27 salary-inflation diagnostic)

    /// Every AI free-agent signing of the current league year, summed. The cap
    /// collapse in task #27 is a *flow* problem — the league's books are a stock
    /// and `SMOKE: diag capRoom` only reports the stock, so it can say the money
    /// is gone but never where it went. This is the flow: how many contracts the
    /// market wrote, what they cost, and what the same men were paid on the deals
    /// that just expired. `agreed − previous` summed over the market IS the
    /// league's annual wage bill increase, and comparing it to the 5-8 % cap
    /// growth is the whole diagnosis in one line.
    ///
    /// Reset per league year by `MultiSeasonSmokeTest`; the app never reads it.
    struct SigningLedger {
        /// Contracts written by `simulateAIFreeAgency` this league year.
        var signings = 0
        /// Sum of the salaries agreed on them (thousands).
        var agreedTotal = 0
        /// Sum of what those same players earned on their PREVIOUS deal — the
        /// contract that just expired (thousands). Zero for anyone who has never
        /// been paid (rookies released into the pool, generated street bodies).
        var previousTotal = 0
        /// Sum of the raw `estimateMarketValue` asks behind those signings, so the
        /// gap between what the market wanted and what it got is visible.
        var askTotal = 0
        /// Signings whose agreed salary came in at least 2× the previous deal —
        /// the second-contract wave, which is where the ratchet lives.
        var raises2x = 0
        /// Task #45: midseason-trade prorations undone at this rollover, and the
        /// salary put back on the books by doing so (thousands). A league that
        /// trades at the deadline must show a non-zero count here every year the
        /// deals carry into.
        var prorationsRestored = 0
        var prorationSalaryRestored = 0

        var summary: String {
            let avgAgreed = signings == 0 ? 0 : agreedTotal / signings
            let avgPrev = signings == 0 ? 0 : previousTotal / signings
            let avgAsk = signings == 0 ? 0 : askTotal / signings
            return "signings=\(signings) avgAgreed=\(avgAgreed) avgPrev=\(avgPrev) "
                + "avgAsk=\(avgAsk) wageBillDelta=\(agreedTotal - previousTotal) raises2x=\(raises2x) "
                + "prorationRestored=\(prorationsRestored)/+\(prorationSalaryRestored)"
        }
    }

    /// See `SigningLedger`. Diagnostic only — nothing in the game reads it.
    static var signingLedger = SigningLedger()

    /// Salary a player earned on the deal that expired at this rollover, kept
    /// only long enough for the ledger above to read it back when he re-signs
    /// (`executeNewLeagueYear` zeroes `annualSalary` the moment a contract runs
    /// out, so by free agency the old number is gone). Diagnostic only — no
    /// schema change for a measurement.
    static var priorSalaryByPlayerID: [UUID: Int] = [:]

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

    /// Deterministic projected asking price for a (soon-to-be) free agent.
    ///
    /// **One demand model, not two.** This used to be a second, independent
    /// price function — market value times a five-case motivation multiplier
    /// (`money 1.20 / fame 1.10 / stats 1.05 / winning 0.90 / loyalty 0.85`)
    /// that both duplicated and contradicted the motivation term inside
    /// `ContractNegotiationEngine.situationBreakdown`, and that knew nothing of
    /// archetype, morale, `motivationState`, leverage, the tag, a holdout, the
    /// GM's standing or an agent's opening theatre. The user negotiated against
    /// `ContractDemand`; every AI GM in the league negotiated against this. Two
    /// markets, one league.
    ///
    /// It is now the demand model's own opening ask, so the number the tampering
    /// rumor mill leaks, the number the AI market bids against and the number
    /// the user hears on the phone are the same number.
    static func projectedAskingPrice(player: Player, salaryCap: Int = 265_000) -> Int {
        agentDemand(player: player, salaryCap: salaryCap).askAmount
    }

    /// The full demand behind ``projectedAskingPrice`` — ask AND floor, which is
    /// what a settlement needs.
    static func agentDemand(player: Player, salaryCap: Int = 265_000) -> ContractDemand {
        ContractNegotiationEngine.demand(
            player: player,
            negotiationType: .freeAgent,
            salaryCap: salaryCap
        )
    }

    /// Build the free-agent market from all players whose contracts have expired.
    /// Asking prices are influenced by market value and the player's personality motivation.
    /// §5.1: a practice-squad player is `teamID == nil` but under contract, so
    /// the `contractYearsRemaining == 0` clause already keeps him off this
    /// market. `!isOnPracticeSquad` is belt-and-braces on that invariant — if a
    /// squad deal ever reached zero years without being dissolved, the market
    /// would otherwise quietly sell 512 players who already have jobs.
    static func generateFreeAgentMarket(allPlayers: [Player], salaryCap: Int = 265_000) -> [FreeAgent] {
        allPlayers
            .filter {
                $0.contractYearsRemaining == 0 && !$0.isFranchiseTagged && !$0.isRetired
                    && !$0.isOnPracticeSquad
            }
            .map { player in
                let demand = agentDemand(player: player, salaryCap: salaryCap)
                let askingPrice = demand.askAmount

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
                    floorPrice: demand.floorAmount,
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

            contract.careerID = player.careerID ?? team.careerID
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

    // MARK: - FA Drama Storyline Event Generation

    /// Generates storyline events when a player is signed in free agency.
    /// Inspects FA Drama engines (CoachReunion / Hometown / MentorPair / Community / RevengeTour /
    /// Loyalty) and persists any matching `FAStorylineEvent` rows to the model context.
    /// Safe to call after every successful FA signing.
    @MainActor
    static func generateStorylineEventsForSigning(
        player: Player,
        signingTeam: Team,
        teamCoaches: [Coach],
        teamRegion: String?,
        teamAbbrevs: [UUID: String],
        allFAs: [Player],
        modelContext: ModelContext
    ) {
        var events: [FAStorylineEvent] = []

        // Coach reunion: any coach on this team previously coached the player?
        if CoachReunionMatcher.hasReunionAvailable(playerID: player.id, teamCoaches: teamCoaches),
           let coach = CoachReunionMatcher.reunionCoach(playerID: player.id, teamCoaches: teamCoaches),
           let evt = CoachReunionMatcher.generateReunionEvent(player: player, coach: coach, teamID: signingTeam.id) {
            events.append(evt)
        }

        // Hometown hero: player's hometown state matches team region.
        if let region = teamRegion,
           HometownDetector.isHometown(player: player, teamRegion: region),
           let evt = HometownDetector.generateHometownEvent(player: player, teamID: signingTeam.id, teamRegion: region) {
            events.append(evt)
        }

        // Mentor / protégé pair: signing the mentor brings the protégé in too.
        if let protégé = MentorPairEngine.protegéFor(player: player, allFAs: allFAs),
           let evt = MentorPairEngine.generateMentorPairEvent(mentor: player, protégé: protégé, teamID: signingTeam.id) {
            events.append(evt)
        }

        // Community impact: civic-tier > 0 generates a press storyline.
        if player.civicTier > 0,
           let evt = CommunityImpactEngine.generateCommunityEvent(player: player, teamID: signingTeam.id, cityName: signingTeam.city) {
            events.append(evt)
        }

        // Revenge tour: player carries an active grudge against a former cutter.
        if player.cutByTeamID != nil,
           let evt = RevengeTourEngine.generateRevengeEvent(player: player, signingTeamID: signingTeam.id, teamAbbrevs: teamAbbrevs) {
            events.append(evt)
        }

        // Milestone: player chasing a personal milestone — judged on his real
        // career line (task #22), not the OVR heuristic fallback.
        let milestoneHistory = MilestoneTracker.history(
            playerID: player.id, careerID: player.careerID, modelContext: modelContext
        )
        if let milestone = MilestoneTracker.activeMilestones(player: player, history: milestoneHistory).first,
           let evt = MilestoneTracker.generateMilestoneEvent(player: player, milestone: milestone, teamID: signingTeam.id) {
            events.append(evt)
        }

        guard !events.isEmpty else { return }
        for evt in events {
            evt.careerID = player.careerID ?? signingTeam.careerID
            modelContext.insert(evt)
        }
        try? modelContext.save()
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
        modelContext: ModelContext,
        career: Career? = nil
    ) -> LeagueYearSummary {
        let playerTeam = allTeams.first { $0.id == playerTeamID }
        let capBefore = playerTeam?.currentCapUsage ?? 0

        var newFAs: [(name: String, position: String, overall: Int, formerTeam: String)] = []

        // TODO §5.5 — settle the season's incentive clauses BEFORE anything
        // below touches a roster.
        //
        // Ordering is load-bearing twice over. It has to run ahead of the expiry
        // loop because `ContractEngine.evaluateIncentives` refuses to bill a club
        // for a man nobody employs, and the loop is about to set `teamID = nil`
        // on every expiring deal — a player who played the whole season and hit
        // his number would otherwise collect nothing simply because his contract
        // also ran out. And the CHARGE has to land after the cap true-up further
        // down, which rebuilds `currentCapUsage` from rostered salaries and would
        // wipe an increment applied here. So the verdicts are computed now and
        // the money is added at the end.
        let incentiveChargeByTeam = evaluateSeasonIncentives(
            allPlayers: allPlayers,
            career: career,
            modelContext: modelContext
        )

        // Task #45 — undo last season's midseason proration FIRST, before any
        // other line reads `annualSalary`.
        //
        // A deadline trade charges the buyer only the checks still to come and
        // writes that prorated figure back onto the player, because
        // `Team.currentCapUsage` is an incrementally maintained ledger and the
        // number charged has to be the number later refunded. The discount is
        // fully earned out the moment the league year turns, so the real base goes
        // back on the row here and the receipt is torn up. Running ahead of the
        // expiry loop is what makes the rest of this function correct without
        // knowing anything about trades: the true-up below then sums the honest
        // salary, and an expiring deal is reported at the money it was really
        // worth instead of at its prorated stub.
        //
        // Players who left the roster in the meantime (cut, retired) are skipped —
        // they are already at 0 and must stay there — but their receipt is still
        // cleared, so a stale full base can never resurface on a later signing.
        for player in allPlayers where player.proratedFullBaseSalary > 0 {
            if player.teamID != nil, player.contractYearsRemaining > 0, !player.isRetired {
                signingLedger.prorationsRestored += 1
                signingLedger.prorationSalaryRestored +=
                    player.proratedFullBaseSalary - player.annualSalary
                player.annualSalary = player.proratedFullBaseSalary
            }
            player.proratedFullBaseSalary = 0
        }

        for player in allPlayers {
            guard player.contractYearsRemaining > 0, !player.isFranchiseTagged else { continue }

            player.contractYearsRemaining -= 1

            if player.contractYearsRemaining == 0 {
                // Player's contract has expired -- becomes free agent
                let formerTeam = allTeams.first { $0.id == player.teamID }
                let teamAbbr = formerTeam?.abbreviation ?? "FA"

                // R23: log the departure for the compensatory-pick formula
                // (only contract EXPIRIES count — cuts never pass through here).
                if let formerTeamID = player.teamID {
                    CompensatoryPickEngine.recordDeparture(playerID: player.id, formerTeamID: formerTeamID)
                }

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
                // Task #27 diagnostic: remember what the expiring deal paid
                // before the number is destroyed, so the signing ledger can
                // price this league year's wage-bill increase.
                priorSalaryByPlayerID[player.id] = player.annualSalary
                ChurnDiag.record(ChurnDiag.expire, player)
                player.teamID = nil
                player.annualSalary = 0
            }
        }

        // Remove franchise tags (they last one year)
        for player in allPlayers where player.isFranchiseTagged {
            player.isFranchiseTagged = false
        }

        // §5.1 — the practice squads dissolve with the league year.
        //
        // A squad deal is written for `PracticeSquadEngine.contractYears`, so the
        // expiry loop above has just taken the last one to zero; this clears the
        // squad markers that went with it and hands all 512 stashed players to
        // the open market. That is the real calendar — practice-squad contracts
        // expire in March and those players are free agents until somebody
        // re-signs them — and it is also what keeps the rest of the offseason
        // honest: from here until the next cutdown day nothing in the league
        // carries a squad flag, so the FA market, the roster refill, the washout
        // pass and the camp development pass all see a normal free agent.
        //
        // Deliberately AFTER the expiry loop and BEFORE the cap true-up: these
        // rows were never on anyone's cap (squad pay is cap-exempt, see the
        // engine header), and the true-up below rebuilds usage from
        // `teamID != nil` rows only, so they cannot leak into it either way.
        PracticeSquadEngine.dissolveSquads(allPlayers: allPlayers)

        // Apply cap growth (~5-8% increase)
        let capGrowth = Double.random(in: 0.05...0.08)
        for team in allTeams {
            team.salaryCap = Int(Double(team.salaryCap) * (1.0 + capGrowth))
        }

        // League-year cap TRUE-UP (task #27). `currentCapUsage` is an
        // incrementally maintained ledger, and the increments leak: dead money
        // from every cut and trade stays on the books FOREVER, so a busy trade
        // market strangles itself — measured over one smoke career, league cap
        // room fell 22% → 3.7% → 0.8% in three seasons and the in-season
        // market died with it. Real dead money ages off within a league year
        // or two; until a per-year dead-cap ledger exists, the honest model is
        // to rebuild each club's usage from its actual current liabilities
        // (rostered salaries) at the rollover — dead cap thus bites for the
        // league year it was incurred and then expires, and any incremental
        // drift the season accumulated is corrected in the same pass.
        var salaryByTeam: [UUID: Int] = [:]
        for player in allPlayers {
            guard let teamID = player.teamID, player.contractYearsRemaining > 0 else { continue }
            salaryByTeam[teamID, default: 0] += player.annualSalary
        }
        for team in allTeams {
            team.currentCapUsage = salaryByTeam[team.id] ?? 0
        }

        // TODO §5.5 — the earned half of the settlement computed at the top of
        // this function. Charged here, immediately after the rebuild, so it is
        // an honest liability of the league year that just opened and expires
        // with it exactly like the dead money the true-up above ages off.
        // Earned = charged, once: the clauses stay on the deal for next season,
        // and nothing here clears the package.
        for team in allTeams {
            guard let charge = incentiveChargeByTeam[team.id], charge > 0 else { continue }
            team.currentCapUsage += charge
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

    // MARK: - Incentive Settlement (TODO §5.5)

    /// Grades every live incentive package against the season that just ended
    /// and returns the cap charge each club owes, in thousands.
    ///
    /// Reads only; the caller decides when the money lands. Returns empty —
    /// after a single `UserDefaults` decode — in every save where nobody
    /// negotiated a clause, which is the overwhelmingly common case, and in
    /// `.sandbox`, where the whole cap is switched off.
    ///
    /// The season graded is `career.currentSeason`: the rollover runs during the
    /// offseason phases, and `WeekAdvancer` does not increment the year until
    /// the roster-cuts → regular-season transition, so the current season IS the
    /// one whose `PlayerSeasonHistory` rows were snapshotted at week 18.
    private static func evaluateSeasonIncentives(
        allPlayers: [Player],
        career: Career?,
        modelContext: ModelContext
    ) -> [UUID: Int] {
        guard let career, career.capMode != .sandbox else { return [:] }
        let packages = ContractIncentiveRegistry.allPackages(careerID: career.id)
        guard !packages.isEmpty else { return [:] }

        let cid = career.id
        let season = career.currentSeason
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.careerID == cid && $0.season == season }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var historyByPlayer: [UUID: PlayerSeasonHistory] = [:]
        for row in rows { historyByPlayer[row.playerID] = row }

        var chargeByTeam: [UUID: Int] = [:]
        for player in allPlayers {
            guard packages[player.id.uuidString]?.isEmpty == false else { continue }
            guard let teamID = player.teamID, let history = historyByPlayer[player.id] else { continue }
            let settlement = ContractEngine.evaluateIncentives(player: player, history: history)
            guard settlement.payoutK > 0 else { continue }
            chargeByTeam[teamID, default: 0] += settlement.payoutK
        }
        return chargeByTeam
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
        simulateAIFreeAgency(
            freeAgents: freeAgents,
            teams: aiTeams,
            modelContext: modelContext,
            capMode: capMode,
            allPlayers: allPlayers
        )
    }

    // MARK: - AI Free Agency Simulation

    /// R39 perf: per-team position-group counts + best OVR, built ONCE from a
    /// roster snapshot and updated incrementally as signings land.
    ///
    /// `assessPositionNeed` re-filters `allPlayers` (~1,700 SwiftData models)
    /// on every call; the bulk FA skip evaluated it per agent × team, which
    /// added up to ~20M attribute reads (~30 s per FreeAgency advance in the
    /// multi-season harness). This index answers the same question from a
    /// dictionary and returns bit-identical need levels.
    struct RosterNeedIndex {
        /// team → position → (count, best overall) for that exact position.
        private var byTeam: [UUID: [Position: (count: Int, best: Int)]] = [:]
        /// team → players currently under contract. Task #27: the market has to
        /// know when a club has run out of ROSTER, not only out of money.
        private var sizeByTeam: [UUID: Int] = [:]

        init(allPlayers: [Player]) {
            for player in allPlayers {
                guard let teamID = player.teamID, !player.isRetired else { continue }
                add(position: player.position, overall: player.overall, to: teamID)
            }
        }

        /// Registers a signing so later need checks see the roster change,
        /// exactly like re-filtering `allPlayers` used to.
        mutating func add(position: Position, overall: Int, to teamID: UUID) {
            var teamMap = byTeam[teamID] ?? [:]
            let current = teamMap[position] ?? (count: 0, best: 0)
            teamMap[position] = (count: current.count + 1, best: max(current.best, overall))
            byTeam[teamID] = teamMap
            sizeByTeam[teamID, default: 0] += 1
        }

        /// Players under contract at this club right now.
        func rosterSize(teamID: UUID) -> Int { sizeByTeam[teamID] ?? 0 }

        /// Same decision table as `assessPositionNeed(team:position:allPlayers:)`.
        func need(teamID: UUID, position: Position) -> PositionNeedLevel {
            let (groupPositions, idealCount) = FreeAgencyEngine.positionGroupInfo(for: position)
            var count = 0
            var bestOVR = 0
            if let teamMap = byTeam[teamID] {
                for groupPosition in groupPositions {
                    if let entry = teamMap[groupPosition] {
                        count += entry.count
                        bestOVR = max(bestOVR, entry.best)
                    }
                }
            }
            if count == 0 || bestOVR < 60 { return .critical }
            let deficit = idealCount - count
            if deficit >= 2 || (deficit >= 1 && bestOVR < 70) { return .high }
            if deficit >= 1 || bestOVR < 75 { return .moderate }
            return .none
        }
    }

    // MARK: - The AI market's budget (task #27)

    /// Players a club will carry out of free agency, leaving the rest of the
    /// 53-man roster for the draft class and camp bodies.
    ///
    /// Free agency runs BEFORE the draft on the league calendar, so a club that
    /// fills all 53 slots in March has spent the money and the spots its rookies
    /// are about to need. The market used to have no roster limit at all: it
    /// signed every expiring contract in the league to somebody — 464 deals in
    /// one measured league year against ~212 actual holes — and
    /// `WeekAdvancer.trimAIRosters` then released the surplus at final cutdowns.
    /// The churn was invisible in the roster counts (they end at 53 either way)
    /// but not in the books: those ~250 extra contracts were signed at market and
    /// paid for out of cap room that the draft class then had to share.
    ///
    /// 46 = 53 − 7: an average draft class is 7-8 picks.
    ///
    /// Task #53 tried 42 — the argument being that the ceiling decides how much
    /// of a roster is built by the market's ordering (`marketAppeal`) and how
    /// much by the roster floor's (`RosterValue.keepScore`), so handing the
    /// floor four more slots a club would tilt the league younger. It measured
    /// the opposite and is left at 46: the floor signs at the veteran minimum
    /// and keeps its picks forever, so moving ~128 roster spots a league year
    /// onto it did not thin the 80+ band (20.3 % → 21.2 %) and cost 0.5 points
    /// of league-mean drift (+0.80 → +1.33). The market, cap reserve and all, is
    /// the more honest builder of the two.
    static let faRosterCeiling = 46

    /// Share of the cap an AI club holds back in free agency.
    ///
    /// The money is not idle — it is committed to things that have not happened
    /// yet when the market opens: the rookie class (measured at ~5-6 % of cap
    /// across the league's ~8 picks a club), in-season injury replacements and
    /// practice-squad churn (`WeekAdvancer.refillAIRosters`), and a deadline
    /// move. None of those paths ask permission from the cap, so if free agency
    /// is allowed to spend to the last dollar the league is guaranteed to end the
    /// year over it — which is exactly what it did: room fell 22.9 % → 0.7 % →
    /// -1.9 % over three seasons and 29 of 32 clubs finished season 3 in the red.
    ///
    /// Derived rather than guessed, from the two bills the market does not pay:
    /// the draft class and the in-season refill cost a measured **6.6 % of cap**
    /// between them (payroll ran from ~100 % straight after free agency to
    /// 106.6 % once both had landed), and the league is asked to open a season
    /// with **8 %** room so the trade market has something to work with. 6.6 + 8
    /// ≈ 15.
    static let capReservePercent = 0.15

    // MARK: - The market's age discount (task #53)

    /// Age from which a free agent's appeal to the market starts decaying, and
    /// the points of appeal each further year costs him.
    ///
    /// ## Why this exists: the market was the composition ratchet
    ///
    /// Task #51 proved the league's §8 pyramid drift is not a development pass
    /// (`diag devsource`: camp + focus + breakout + gameXP sum to +0.07 mean OVR
    /// a season). Task #53 measured the other half with `ChurnDiag`, and the
    /// funnel named itself in one line — season 2027 of a 4-season smoke:
    ///
    ///     expire=1045/ovr67.9/age25.4   faSign=489/ovr79.2/age27.6
    ///     washout=354/ovr61.7/age25.3   refill=189/ovr71.0/age25.9
    ///
    /// A thousand men hit the market at a mean of 67.9 OVR and 25.4 years old.
    /// The market re-signed 489 of them at **+11.3 OVR and +2.2 years** on that
    /// mean, and the 354 it passed over — 61.7 OVR, 25.3 years old — were fed
    /// straight to the washout pass and left the league for good. Repeat that
    /// four times and the rostered population is old and top-heavy by
    /// construction: 80+ went 18.2 % → 22.7 %, 90+ drifted +1.4 pp and the 33+
    /// share +1.7 pp, all with league development doing essentially nothing.
    ///
    /// The cause was a one-line asymmetry between the two halves of roster
    /// management. `WeekAdvancer.trimAIRosters` and `refillAIRosters` both order
    /// by `RosterValue.keepScore`, which discounts age at 3.2 points a year past
    /// 25 — cheap youth beats expensive age at the back of a roster. This
    /// market ordered by **raw `overall`**, which discounts it by nothing at
    /// all, and `ContractEngine.estimateMarketValue` then made the older man
    /// *cheaper* as well. So the same league cut on youth and signed on age,
    /// every league year, and the men it kept were the ones a real front office
    /// would have let walk.
    ///
    /// ## Why the market's discount is GENTLER than the cutdown's
    ///
    /// The two questions are not the same question. Cutdown day is choosing
    /// between the 50th and the 54th man, where a 31-year-old journeyman offers
    /// nothing a camp body does not — hence 3.2 points a year from 25. The
    /// market is pricing a STARTER, where quality still buys years: clubs do
    /// sign 30-year-old Pro Bowlers, they just do not sign them ahead of a
    /// 25-year-old of similar standard. 2.0 points a year from 26 is the
    /// discount that reproduces that ordering — a 79-OVR 30-year-old (67)
    /// now falls behind a 70-OVR 25-year-old with an 80 ceiling (73.5), which
    /// is the swap the funnel above was making backwards.
    ///
    /// The rate matches `RosterValue.keepScore` exactly, and that is the point:
    /// the two halves of roster management now answer the same question the same
    /// way. The gentler 2.0-2.4 tried first did close the AGE pyramid (33+ drift
    /// went from +1.9 pp to −2.1 pp) but barely moved the QUALITY one — 80+ fell
    /// only 23.2 % → 21.6 % — because the men the §8 80+ band is about are 27-to-30
    /// and a 2.4-a-year discount hands them 5-to-12 points of head start over the
    /// draft class competing for their roster spot. At 3.2 a 28-year-old at 80
    /// grades 70.4 and a 25-year-old at 70 with a 80 ceiling grades 74.5, which
    /// is the ordering cutdown day has always used.
    ///
    /// The CAP is what keeps stars signable. The discount is linear because
    /// decline is, but "unemployed" is not a linear consequence of it: a
    /// 32-year-old at 88 is still one of the best hundred players alive and a
    /// club will pay him for the two years he has left. Uncapped, 3.2 a year
    /// from 25 put him at 65 — below the market's own median appeal, i.e. out
    /// of football, which is absurd. Capped at 14 he grades 74 and signs in the
    /// first wave, while a 30-year-old at 79 (65) does not. The cap binds from
    /// age 30, which is exactly where the question stops being "how much has he
    /// declined" and starts being "how many years are left".
    ///
    /// Saturating EARLIER (11, binding at 28.4) was tried, to broaden a veteran
    /// tier that had come out elite-only — 153 men at a mean of 84.8 OVR where
    /// the generator's cross-section carries ~15 % of the league at eight-plus
    /// years and a mean of 78.9. It broadened the tier by a point and cost the
    /// quality bands more than it bought: 80+ 20.3 % → 21.2 %, league-mean drift
    /// +0.80 → +1.33. A softer discount on 30-year-olds is a softer discount on
    /// the 30-year-olds who are 82, and those are the ones the band counts.
    static let marketAgeDiscountFrom = 25
    static let marketAgeDiscountPerYear = 3.2
    static let marketAgeDiscountCap = 14.0

    /// How much of a young player's untapped ceiling the market counts as
    /// present appeal, and the service window it applies over.
    ///
    /// The mirror of `RosterValue.upsidePremium` (0.45 over 3 years), same rate
    /// and one year wider: free agency is a market for men who have already
    /// played, so a fourth-year player's remaining ceiling is still worth
    /// something here the way a tenth-year player's is not.
    static let marketUpsidePremium = 0.45
    static let marketUpsideYears = 4

    /// Order the free-agent market signs in — `overall`, discounted for age and
    /// credited for untapped ceiling. See `marketAgeDiscountFrom` for the
    /// measurement this replaced and why the constants are what they are.
    ///
    /// This changes WHO gets the roster spots, not how many: the loop below
    /// still signs until clubs hit `faRosterCeiling` or their cap reserve, so
    /// the market writes the same number of contracts either way.
    static func marketAppeal(_ player: Player) -> Double {
        var score = Double(player.overall)
        score -= min(
            marketAgeDiscountCap,
            Double(max(0, player.age - marketAgeDiscountFrom)) * marketAgeDiscountPerYear
        )
        if player.yearsPro <= marketUpsideYears {
            score += Double(max(0, player.truePotential - player.overall)) * marketUpsidePremium
        }
        return score
    }

    /// Let AI-controlled teams sign available free agents based on need and cap room.
    /// In sandbox cap mode the cap-room filter is dropped so any team can sign anyone.
    /// R23: when `allPlayers` is provided, teams that actually NEED the position
    /// jump the queue (critical > high > moderate) instead of pure cap-space order,
    /// so bulk-simulated FA follows the same logic as the interactive rounds.
    ///
    /// Task #27 adds the two budget constraints a market needs to be a market:
    /// clubs stop at `faRosterCeiling` players and never spend below
    /// `capReservePercent` of their cap. See both for the measurements.
    ///
    /// §5.1 adds the third thing a market has: a REPUTATION term. Which club a
    /// free agent picks out of the shortlist used to be `randomElement()` —
    /// uniform, so a building famous for developing players had no pull at all.
    /// `CoachingEngine.developmentAppeal` is now that pull (0.85-1.15), applied
    /// as a weight on the same shortlist rather than as a new filter, so it can
    /// tilt a coin-flip without ever overriding need or cap room.
    static func simulateAIFreeAgency(
        freeAgents: [FreeAgent],
        teams: [Team],
        modelContext: ModelContext,
        capMode: CapMode = .simple,
        allPlayers: [Player]? = nil
    ) {
        // Order the market by APPEAL, not by raw `overall` (task #53). The
        // elite still go first — an 88-OVR 32-year-old grades 76 against a
        // league mean in the low 70s — but a 30-year-old no longer outranks a
        // 25-year-old of the same standard, which is the swap that was quietly
        // aging the league one league year at a time. See `marketAppeal`.
        let sortedAgents = freeAgents.sorted { marketAppeal($0.player) > marketAppeal($1.player) }

        // R39 perf: one roster snapshot for every need lookup below.
        var needIndex: RosterNeedIndex?
        if let rosterPlayers = allPlayers, !rosterPlayers.isEmpty {
            needIndex = RosterNeedIndex(allPlayers: rosterPlayers)
        }

        // §5.1 — the staff's developer reputation, one fetch for the whole
        // market rather than one per free agent (the loop below runs a few
        // hundred times per league year).
        let allCoaches = (try? modelContext.fetch(FetchDescriptor<Coach>())) ?? []
        let coachesByTeam = Dictionary(
            grouping: allCoaches.filter { $0.teamID != nil },
            by: { $0.teamID! }
        )
        var appealByTeam: [UUID: Double] = [:]
        for team in teams {
            appealByTeam[team.id] = CoachingEngine.developmentAppeal(
                teamID: team.id,
                coaches: coachesByTeam[team.id] ?? []
            )
        }

        for agent in sortedAgents {
            // Skip players who were already signed this cycle
            guard agent.player.teamID == nil else { continue }

            // In sandbox mode, every team is eligible regardless of cap.
            var eligibleTeams: [Team]
            switch capMode {
            case .simple, .realistic:
                eligibleTeams = teams
                    .filter { team in
                        // Task #27: a club needs room AND a roster spot, and the
                        // room it spends is what is left ABOVE its reserve. The
                        // roster test only applies when a roster snapshot exists;
                        // without one the market falls back to the old cap-only
                        // rule rather than silently signing nobody.
                        let reserve = Int(Double(team.salaryCap) * capReservePercent)
                        guard team.availableCap - reserve >= agent.askingPrice else { return false }
                        guard let needIndex else { return true }
                        return needIndex.rosterSize(teamID: team.id) < faRosterCeiling
                    }
                    .sorted { $0.availableCap > $1.availableCap }
            case .sandbox:
                eligibleTeams = teams.shuffled()
            }

            // R23: need-first ordering when roster data is available.
            let agentPosition = agent.player.position
            if let needIndex {
                func needRank(_ team: Team) -> Int {
                    switch needIndex.need(teamID: team.id, position: agentPosition) {
                    case .critical: return 3
                    case .high:     return 2
                    case .moderate: return 1
                    case .none:     return 0
                    }
                }
                let ranked = eligibleTeams.map { (team: $0, rank: needRank($0)) }
                // Teams with any need come first; ties broken by cap space order.
                let needy = ranked.filter { $0.rank > 0 }.sorted { $0.rank > $1.rank }.map(\.team)
                let rest = ranked.filter { $0.rank == 0 }.map(\.team)
                eligibleTeams = needy + rest
            }

            // Pick from the top interested teams (capped by marketInterest)
            let candidateCount = min(agent.marketInterest, eligibleTeams.count)
            guard candidateCount > 0 else { continue }

            let candidates = Array(eligibleTeams.prefix(candidateCount))

            // Pick the winner out of the shortlist, weighted by how good the
            // building is at developing players (§5.1). With every appeal at
            // 1.0 this is exactly the uniform `randomElement()` it replaced.
            guard let winningTeam = weightedPick(
                candidates,
                weight: { appealByTeam[$0.id] ?? 1.0 }
            ) else { continue }

            // The AI GM negotiates against the SAME demand model the user does:
            // he lands somewhere between the agent's floor and his opening ask,
            // never below the floor. The old `ask × random(0.85…1.0)` had no
            // floor under it at all, which is how an AI club could buy a man for
            // less than the user's agent would ever have taken.
            let minimum = max(Int(0.0028 * Double(winningTeam.salaryCap)), 750)
            let floor = min(agent.floorPrice, agent.askingPrice)
            let settlement = Double(floor) + Double(agent.askingPrice - floor) * Double.random(in: 0...1)
            let agreedSalary = max(Int(settlement), minimum)
            let agreedYears = agent.desiredYears

            // Task #27 diagnostic: record the flow before the signing lands.
            let priorSalary = priorSalaryByPlayerID[agent.player.id] ?? 0
            signingLedger.signings += 1
            signingLedger.agreedTotal += agreedSalary
            signingLedger.previousTotal += priorSalary
            signingLedger.askTotal += agent.askingPrice
            if priorSalary > 0, agreedSalary >= priorSalary * 2 { signingLedger.raises2x += 1 }

            // Route the signing through the cap-mode-aware wrapper so sandbox
            // skips cap accounting entirely.
            ContractEngine.signPlayer(
                player: agent.player,
                years: agreedYears,
                annualSalary: agreedSalary,
                team: winningTeam,
                capMode: capMode
            )

            ChurnDiag.record(ChurnDiag.faSign, agent.player)

            // Keep the need index in sync with the roster change (the old
            // per-call filter saw the new teamID on the next agent too).
            needIndex?.add(position: agentPosition, overall: agent.player.overall, to: winningTeam.id)
        }
    }

    /// Roulette-wheel pick over `weight`. Returns `nil` for an empty list and
    /// degenerates to a uniform draw when every weight is equal, which is what
    /// makes it a safe drop-in for `randomElement()`.
    private static func weightedPick<T>(_ items: [T], weight: (T) -> Double) -> T? {
        guard !items.isEmpty else { return nil }
        let weights = items.map { max(0.0, weight($0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return items.randomElement() }
        var roll = Double.random(in: 0..<total)
        for (index, w) in weights.enumerated() {
            roll -= w
            if roll < 0 { return items[index] }
        }
        return items.last
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
    /// Internal because the R23 signing-interest meter reuses the same grouping.
    static func positionGroupInfo(for position: Position) -> (positions: [Position], idealCount: Int) {
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
        // All players for need assessment; fall back to empty if not provided.
        // R39 perf: one snapshot index instead of re-filtering ~1,700 players
        // per agent × team (same fix as simulateAIFreeAgency).
        let rosterPlayers = allPlayers ?? []
        let needIndex = rosterPlayers.isEmpty ? nil : RosterNeedIndex(allPlayers: rosterPlayers)

        for fa in freeAgents {
            guard fa.player.teamID == nil else { continue }
            guard fa.player.overall >= targetMinOVR else { continue }

            var bids: [AIBid] = []

            for team in aiTeams {
                // Skip cap gating entirely in sandbox mode.
                //
                // Task #27: the same reserve the bulk market keeps. This is the
                // path a real career's free-agent weeks run through, so if only
                // `simulateAIFreeAgency` budgeted, the user's league would still
                // spend itself broke — the two are one market and have to price
                // against one bank balance.
                if capMode != .sandbox {
                    let reserve = Int(Double(team.salaryCap) * capReservePercent)
                    guard team.availableCap - reserve >= fa.askingPrice else { continue }
                    if let needIndex, needIndex.rosterSize(teamID: team.id) >= faRosterCeiling {
                        continue
                    }
                }

                // Assess this team's need for the player's position
                let need: PositionNeedLevel
                if let needIndex {
                    need = needIndex.need(teamID: team.id, position: fa.player.position)
                } else {
                    // Fallback: use old quality-based approach when roster data unavailable
                    let qualityFactor = Double(fa.player.overall - 60) / 40.0
                    if qualityFactor > 0.5 { need = .high }
                    else if qualityFactor > 0.25 { need = .moderate }
                    else { need = .none }
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
                    // 30 % of SPENDABLE room, not of nominal room — the reserve
                    // is not the club's to bid with (task #27).
                    let reserve = Int(Double(team.salaryCap) * capReservePercent)
                    let spendable = max(0, team.availableCap - reserve)
                    let maxBid = Int(Double(spendable) * 0.30)
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
    /// R23: when `allPlayers` is provided, every bid is also weighed by the
    /// projected ROLE on that roster (would he start, or sit behind a better
    /// player?), and a hosted facility visit boosts the user's offer.
    static func resolvePlayerDecision(
        player: Player,
        playerOffer: (salary: Int, years: Int)?,
        aiBids: [AIBid],
        round: Int,
        allTeams: [Team]? = nil,
        allPlayers: [Player]? = nil,
        userTeamID: UUID? = nil,
        hostedVisit: Bool = false
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
            let rosterTeamID: UUID?
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
                teamRecord: teamData.map { (wins: $0.wins, losses: $0.losses) },
                rosterTeamID: aiBid.teamID
            )
        }

        if let offer = playerOffer {
            // The user's own club is a club. Its record was `nil` here, which
            // meant a `.winning`-motivated free agent gave every AI bidder a
            // record bonus and the user none — his 13-3 season was worth exactly
            // nothing at the table, and a legacy veteran could not tell a
            // contender from a tyre fire if the contender was the user.
            let ownTeam = userTeamID.flatMap { id in teams.first { $0.id == id } }
            allBids.append(Bid(
                teamID: nil,
                teamName: "Your Team",
                salary: offer.salary,
                years: offer.years,
                isPlayer: true,
                mediaMarket: ownTeam?.mediaMarket,
                teamRecord: ownTeam.map { (wins: $0.wins, losses: $0.losses) },
                rosterTeamID: userTeamID
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

            // R23: hosted facility visit — the player got the tour, met the
            // staff, saw the plan. Clear, explainable edge for the host team.
            if bid.isPlayer && hostedVisit {
                score *= 1.15
            }

            // R23: role factor — players favor rosters where they'd start.
            // Stats-motivated players weigh it heavily; everyone weighs it some.
            if let rosterPlayers = allPlayers, !rosterPlayers.isEmpty,
               let rosterTeamID = bid.rosterTeamID {
                let role = SigningInterestEngine.roleScore(
                    player: player,
                    teamID: rosterTeamID,
                    allPlayers: rosterPlayers
                )
                let roleWeight = (player.personality.motivation == .stats) ? 0.30 : 0.12
                score *= 1.0 + (role - 0.5) * roleWeight
            }

            // Longer deals valued more by young players
            if player.age < player.position.peakAgeRange.lowerBound {
                score *= 1.0 + Double(bid.years) * 0.05
            }

            // **The legacy veteran's half of the Brady clause.**
            //
            // The extension side of this stance is a discount for a contender
            // (`ContractNegotiationEngine`'s team term). This is the free-agent
            // side, and it has to be strong enough to actually LOSE the man a
            // cheque: an aging great choosing a winner over money is only a
            // story if the money sometimes loses. At ±25 % it takes roughly a
            // 50 % overpay for a 4-12 club to outbid a contender — which is
            // about what it took in real life, and never a certainty either way.
            score *= legacyVeteranPreference(player: player, record: bid.teamRecord)

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

    // MARK: - Legacy Veteran Preference

    /// How much an aging great wants to play for THIS club, as a multiplier on
    /// the money it is offering.
    ///
    /// `1.0` for everybody who is not a legacy veteran, so this is a no-op on
    /// the overwhelming majority of the market — and a deliberate no-op on the
    /// AI-vs-AI pass, which never calls `resolvePlayerDecision` at all. The
    /// stance belongs to the decisions a player actually makes between named
    /// suitors, not to the bulk market's cap arithmetic.
    ///
    /// A missing record reads as 1.0 rather than as a loser: "I could not find
    /// out how this team is doing" is not a reason to walk away from it.
    static func legacyVeteranPreference(
        player: Player,
        record: (wins: Int, losses: Int)?
    ) -> Double {
        guard ContractNegotiationEngine.isLegacyVeteran(player), let record else { return 1.0 }
        let played = record.wins + record.losses
        guard played >= 6 else { return 1.0 }
        let winPct = Double(record.wins) / Double(played)
        // −25 % at winless, +25 % at unbeaten, straight through 1.0 at .500.
        return 1.0 + (winPct - 0.5) * 0.5
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
