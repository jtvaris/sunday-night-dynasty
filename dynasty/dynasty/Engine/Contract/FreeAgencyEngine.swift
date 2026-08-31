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
    static func projectedAskingPrice(player: Player, salaryCap: Int) -> Int {
        agentDemand(player: player, salaryCap: salaryCap).askAmount
    }

    /// The full demand behind ``projectedAskingPrice`` — ask AND floor, which is
    /// what a settlement needs.
    static func agentDemand(player: Player, salaryCap: Int) -> ContractDemand {
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
    static func generateFreeAgentMarket(allPlayers: [Player], salaryCap: Int) -> [FreeAgent] {
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

    /// What a completed signing did to the club's books.
    ///
    /// **The acceptance-time backstop** (cap-compliance wave). Committed cap
    /// (`CommittedCapLedger`) stops the user PROMISING more than he has, but it
    /// cannot be the only defence, because not every signing arrives through an
    /// offer that was reserved: a bidding war can be resolved at a number the
    /// club last quoted a round ago, a legacy save carries no reservations at
    /// all, and the draft class, a fifth-year option and a trade all charge the
    /// cap without ever passing through free agency.
    ///
    /// So the deal always COMPLETES — a player who accepted an offer signs it,
    /// full stop; a game that silently voided an accepted contract would be
    /// lying about the one moment the user was waiting for — and the breach is
    /// reported instead. From there the compliance workspace and the week-advance
    /// gate take over: the club is over the cap, it is told so, and it cannot
    /// advance the week until it is not.
    struct SigningOutcome {
        /// The per-year cap charge the deal created, in thousands.
        let capCharge: Int
        /// Whether the club is over the cap AFTER the signing.
        let breachedCap: Bool
        /// How far over, in thousands. Zero when compliant.
        let overage: Int
    }

    /// Sign a free agent to a team. Works in all cap modes.
    /// - Simple: writes annual salary into team cap usage.
    /// - Realistic: builds a full Contract with escalating/front-loaded structure.
    /// - Sandbox: stamps the player onto the roster but skips any cap accounting,
    ///   so the team can sign unlimited players regardless of cap room.
    ///
    /// Returns the ``SigningOutcome`` — the charge, and whether it put the club
    /// over the cap. Discardable so the AI paths, which check affordability
    /// BEFORE they call (`signFreeAgentAI`), stay unchanged.
    @discardableResult
    static func signFreeAgent(
        player: Player,
        team: Team,
        years: Int,
        salary: Int,
        capMode: CapMode,
        modelContext: ModelContext
    ) -> SigningOutcome {
        let usageBefore = team.currentCapUsage

        switch capMode {
        case .simple:
            ContractEngine.signPlayerSimple(
                player: player,
                years: years,
                annualSalary: salary,
                team: team
            )

        case .realistic:
            // Build a realistic contract with proper salary structure.
            //
            // #102 F5 — the bonus is the STABLE draw, not a fresh random one, so
            // `ContractEngine.projectedCapHit` (what the reservation ledger
            // holds when the offer goes out) and `contract.capHit` (what this
            // line charges when it is accepted) are the same number. The band it
            // is drawn from is unchanged; only its unpredictability is gone, and
            // an unpredictable charge is precisely what made the promise
            // unreservable.
            let contract = ContractEngine.buildRealisticContract(
                playerID: player.id,
                teamID: team.id,
                annualSalary: salary,
                years: years,
                playerAge: player.age,
                noTrade: false,
                signingBonus: ContractEngine.stableSigningBonus(
                    playerID: player.id, annualSalary: salary
                )
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

        // A signed deal is no longer a promise — whatever this man's offer was
        // reserving, the contract now charges for real. Releasing the row here
        // rather than at the call site means every signing door closes the
        // commitment, including the ones that resolve a bidding war without the
        // offer screen ever being reopened.
        CommittedCapLedger.release(playerID: player.id, careerID: player.careerID)

        let status = CapManagementEngine.complianceStatus(team: team, capMode: capMode)
        return SigningOutcome(
            capCharge: team.currentCapUsage - usageBefore,
            breachedCap: !status.isCompliant,
            overage: status.overage
        )
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
    ///
    /// **Runs at most once per league year.** Everything below is destructive and
    /// none of it is idempotent: the expiry loop decrements every contract in the
    /// league, cap growth compounds, a whole cohort is emptied onto the market and
    /// `resignAIOwnCore` hands out another 96 retentions. The only guard used to
    /// be `NewLeagueYearView`'s `@State hasExecuted`, which dies with the view —
    /// so backing out of that screen and re-entering it before pressing Continue
    /// ran the entire rollover twice. The guard therefore lives HERE rather than
    /// on either screen, which is also what covers the second entry point
    /// (`WeekAdvancer`'s skipped-FA fallback) with the same line.
    ///
    /// `career.currentSeason` is the identifier because it is the one thing that
    /// does not move across the offseason: `WeekAdvancer` increments the year at
    /// the roster-cuts → regular-season transition, months after this function
    /// runs, so every offseason phase of a given league year reads the same
    /// number. See ``Career/lastRolloverSeason``.
    ///
    /// A blocked re-entry returns a summary of the world AS IT IS — no new free
    /// agents, cap before == cap after — which is the honest answer to "what did
    /// this transition change": nothing, it already happened.
    ///
    /// A `nil` career (harness, previews) has nothing to stamp and is run
    /// unguarded, exactly as before.
    static func executeNewLeagueYear(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        modelContext: ModelContext,
        career: Career? = nil
    ) -> LeagueYearSummary {
        let playerTeam = allTeams.first { $0.id == playerTeamID }
        let capBefore = playerTeam?.currentCapUsage ?? 0

        if let career, career.lastRolloverSeason >= career.currentSeason {
            return LeagueYearSummary(
                newFreeAgents: [],
                playerTeamCapBefore: capBefore,
                playerTeamCapAfter: capBefore,
                capFreed: 0,
                notableFreeAgents: [],
                totalFreeAgentCount: 0
            )
        }
        // Stamped at the TOP of the successful run, before anything mutates, so a
        // crash or an early return further down can never leave the save in a
        // state where half the rollover has landed and the guard still says it
        // has not.
        career?.lastRolloverSeason = career?.currentSeason ?? 0

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

        // Cap-compliance wave — the restructure bill comes due.
        //
        // Sits immediately after the #45 proration restore and for exactly the
        // same reason: both are receipts for a discount that was only ever good
        // for one league year, both have to be torn up before anything else
        // reads `annualSalary`, and both MUST run ahead of the task-#27 cap
        // true-up further down, which rebuilds every club's `currentCapUsage`
        // by summing that field. Restore late and the true-up banks the relief
        // permanently — which is precisely how a restructure would turn into
        // free money.
        //
        // Two motions, in order:
        //
        //   1. `restructureReliefK` — base salary converted this year — goes
        //      back onto the books. The club got ONE year of relief.
        //   2. the carry clock ticks. While it runs, `restructureProrationK`
        //      stays folded into `annualSalary` (that is the price of the
        //      relief, charged in every remaining year); when it reaches zero
        //      the slice comes off and the ledger resets.
        //
        // Net effect on a 3-year, $10M deal restructured at $9.25M: $3.8M this
        // year, $13.1M in each of the next two, $10M again after that. The club
        // saved $6.2M and paid $3.1M twice for it.
        for player in allPlayers where player.restructureReliefK > 0 || player.restructureCarryYears > 0 {
            let stillEmployed = player.teamID != nil
                && player.contractYearsRemaining > 0
                && !player.isRetired

            guard stillEmployed else {
                // Cut, retired or otherwise gone: `applyRelease` already charged
                // the acceleration to the club that owed it. Clear the receipt
                // so it cannot resurface on a later contract.
                player.restructureReliefK = 0
                player.restructureProrationK = 0
                player.restructureCarryYears = 0
                continue
            }

            if player.restructureReliefK > 0 {
                player.annualSalary += player.restructureReliefK
                player.restructureReliefK = 0
            }

            if player.restructureCarryYears > 0 {
                player.restructureCarryYears -= 1
                if player.restructureCarryYears == 0 {
                    player.annualSalary = max(0, player.annualSalary - player.restructureProrationK)
                    player.restructureProrationK = 0
                }
            }
        }

        // Task #127 — the franchise tag's money lands HERE, in the league year it
        // was always a decision about.
        //
        // Ordering, all three constraints load-bearing and all three the same
        // ones `settleFifthYearOptions` below is placed by:
        //
        //   • AFTER the #45 proration restore and the restructure tick, because
        //     the tag OVERWRITES `annualSalary` and both of those write it — a
        //     tag settled first would be re-inflated by `restructureReliefK` a
        //     dozen lines later, which is bug (1) in `applyNegotiatedDeal`'s #102
        //     F6 note in a new costume;
        //   • BEFORE `resignAIOwnCore`, whose retention budget is built from the
        //     payroll that survives this rollover — a tag is exactly such a
        //     commitment, so the club cannot also promise that money elsewhere;
        //   • BEFORE the expiry loop and the cap true-up, so the tag number is
        //     what the true-up sums for the new league year.
        //
        // The contract map is built once here and used twice — the settlement
        // below rewrites the row of every deferred extension that binds this
        // year, and the compliance sweep at the bottom reads the same rows.
        let contractDescriptor = FetchDescriptor<Contract>()
        let allContracts = (try? modelContext.fetch(contractDescriptor)) ?? []
        let contractsByPlayer = Dictionary(
            allContracts.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        settleFranchiseTags(
            allPlayers: allPlayers,
            allTeams: allTeams,
            career: career,
            contractsByPlayer: contractsByPlayer
        )

        // Task #90 — the fifth-year option deadline, and the first money
        // decision of the league year.
        //
        // Ordering, both halves load-bearing: AFTER the proration restore (an
        // option is priced against the honest base salary it replaces, not a
        // deadline stub) and BEFORE `resignAIOwnCore`, whose retention budget is
        // built from the payroll that survives this rollover — a picked-up
        // option is precisely such a commitment, so it has to be on the books
        // before a club decides what it can still promise its own free agents.
        // Also, necessarily, before the expiry loop: the whole window is defined
        // pre-decrement and `contractYearsRemaining += 1` here is what that
        // loop's `-= 1` cancels. See `settleFifthYearOptions`.
        settleFifthYearOptions(
            allPlayers: allPlayers,
            allTeams: allTeams,
            userTeamID: playerTeamID,
            capMode: career?.capMode ?? .simple,
            career: career
        )

        // Task #89 — the AI's own final push. Every other club gets to keep a
        // bounded number of its own expiring core before the market opens, the
        // way the user does on `FinalPushView`. Runs AFTER the proration restore
        // (so a retention is priced against the honest base, not a deadline
        // stub) and BEFORE the expiry loop (which is what makes `years + 1`
        // land on `years`). See `resignAIOwnCore`.
        resignAIOwnCore(
            allPlayers: allPlayers,
            allTeams: allTeams,
            userTeamID: playerTeamID,
            season: career?.currentSeason ?? 0,
            capMode: career?.capMode ?? .simple
        )

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

                // Remove from team cap — unless he was a camp body, who was
                // never on it (#205a, `OFFSEASON_ROSTER_PLAN.md` §3.1). Nothing
                // should be able to reach this line still flagged (the flag
                // clears at the cutdown two phases before any rollover), which
                // is exactly why the guard is here: the invariant is "no path in
                // the game credits a club for a camp body", and an invariant
                // with one unguarded door is a bug waiting for a save file.
                if let team = formerTeam, !CampRosterEngine.isCampBody(player) {
                    team.currentCapUsage -= player.annualSalary
                }
                CampRosterEngine.clearCampBodyStatus(player)
                // Task #27 diagnostic: remember what the expiring deal paid
                // before the number is destroyed, so the signing ledger can
                // price this league year's wage-bill increase.
                priorSalaryByPlayerID[player.id] = player.annualSalary
                ChurnDiag.record(ChurnDiag.expire, player)
                player.teamID = nil
                player.annualSalary = 0
                // A tag year that runs out is a tag year that is over: the man is
                // a free agent, and his next deal is an ordinary signing rather
                // than a replacement of a charge nobody is carrying.
                player.franchiseTagSeason = 0
                // The deal is over, so the restructure it carried is over too —
                // the tick above already charged this league year's slice, and a
                // free agent must not walk into his next contract with the
                // previous club's acceleration still attached to him.
                player.restructureReliefK = 0
                player.restructureProrationK = 0
                player.restructureCarryYears = 0
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
        let capGrowth = Double.random(in: ContractEngine.capGrowthRange)
        for team in allTeams {
            team.salaryCap = Int(Double(team.salaryCap) * (1.0 + capGrowth))
        }

        // League-year cap TRUE-UP (task #27, ledger added by D2).
        //
        // `currentCapUsage` is an incrementally maintained ledger and the
        // increments leak, so the rollover rebuilds each club's usage from its
        // actual current liabilities and any drift the season accumulated is
        // corrected in the same pass. That half is unchanged and is why this
        // exists at all: before it, dead money stayed on the books FOREVER and a
        // busy trade market strangled itself — measured over one smoke career,
        // league cap room fell 22 % → 3.7 % → 0.8 % in three seasons and the
        // in-season market died with it.
        //
        // What CHANGED (D2): the rebuild used to be `rostered salaries` and
        // nothing else, which erased every dollar of dead money at every
        // rollover. The comment that used to sit here called that a placeholder
        // "until a per-year dead-cap ledger exists" — it exists now
        // (`Team.deadCapCurrentYear` / `deadCapNextYear`), so the rebuild is
        // `rostered salaries + what the club still owes`. Dead money now ages
        // over one or two league years by the June 1-shaped split
        // `CapManagementEngine.bookDeadMoney` applies, and then expires. It
        // cannot accumulate forever — nothing is ever carried more than one
        // year past the year it was booked — so the leak this true-up was
        // written to stop stays stopped.
        //
        // Why it matters beyond accounting: a catastrophic cap sheet used to
        // self-clear in a single offseason, which made `.capHell` a starting
        // condition rather than a state and meant no contract decision could
        // follow a club for two years. A blunder with no lasting cost is not a
        // blunder.
        //
        // Camp bodies are excluded (#205a, `OFFSEASON_ROSTER_PLAN.md` §3.1):
        // their minimum salary is cap-exempt while they are carried, and this
        // rebuild is the ledger's ground truth, so it must not be able to
        // disagree with the exemption. Defensive rather than load-bearing —
        // `CampRosterEngine.settleCampBodies` clears every flag at cutdown, four
        // phases before the next rollover reaches this line — and kept for
        // exactly that reason: if a leak ever does survive to here, the true-up
        // should correct it, not ratify it.
        var salaryByTeam: [UUID: Int] = [:]
        for player in allPlayers {
            guard let teamID = player.teamID,
                  player.contractYearsRemaining > 0,
                  !CampRosterEngine.isCampBody(player) else { continue }
            salaryByTeam[teamID, default: 0] += player.annualSalary
        }
        for team in allTeams {
            // Age the ledger one year FIRST — what was owed next year is owed
            // now — then rebuild usage on top of what is genuinely still owed.
            let carried = CapManagementEngine.rollDeadMoneyForward(on: team)
            team.currentCapUsage = (salaryByTeam[team.id] ?? 0) + carried
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

        // Cap-compliance wave — the other 31 clubs settle their own books.
        //
        // LAST, because it has to see the finished ledger: the true-up above and
        // the incentive charge above that are both inputs to "is this club
        // legal", and healing before either would be healing against a number
        // that is about to change. The user's club is deliberately excluded —
        // the whole point of the compliance workspace is that HE decides which
        // contract pays for it. See `CapManagementEngine.selfHealCapCompliance`
        // for why this is restructure-only and why it cannot move the market.
        let capMode = career?.capMode ?? .simple
        if capMode != .sandbox {
            var rosterByTeam: [UUID: [Player]] = [:]
            for player in allPlayers {
                guard let teamID = player.teamID, teamID != playerTeamID else { continue }
                rosterByTeam[teamID, default: []].append(player)
            }
            for team in allTeams where team.id != playerTeamID {
                CapManagementEngine.selfHealCapCompliance(
                    team: team,
                    players: rosterByTeam[team.id] ?? [],
                    contractsByPlayer: contractsByPlayer,
                    capMode: capMode,
                    salaryCap: team.salaryCap
                )
            }
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
        capMode: CapMode = .simple,
        season: Int
    ) {
        // Use average cap across all teams for market valuation
        let avgCap = allTeams.isEmpty ? ContractEngine.openingSalaryCap : allTeams.reduce(0) { $0 + $1.salaryCap } / allTeams.count
        let freeAgents = generateFreeAgentMarket(allPlayers: allPlayers, salaryCap: avgCap)
        let aiTeams = allTeams.filter { $0.id != playerTeamID }
        simulateAIFreeAgency(
            freeAgents: freeAgents,
            teams: aiTeams,
            modelContext: modelContext,
            capMode: capMode,
            allPlayers: allPlayers,
            season: season
        )
    }

    // MARK: - The market closes exactly once (task #93 F9)

    /// ``simulateRemainingFA``, at most once per career league year.
    ///
    /// The stamp is ``Career/lastBulkMarketSeason`` — on the MODEL, not in a
    /// static table. The three doors into the bulk market (the Skip button,
    /// `WeekAdvancer`'s skipped-FA fallback and its mop-up) are not all reached
    /// in one process: Skip runs the market and persists
    /// `freeAgencyStep == .complete`, and a user who quits there and comes back
    /// hits the mop-up on the next Advance Week with a fresh, empty process. An
    /// in-memory guard is blind to exactly that sequence and would open the
    /// market a second time inside one league year — a second wave of contracts
    /// against the #53 calibration, a second helping of cap spend and a
    /// double-counted `signingLedger`.
    ///
    /// A `nil` career (harness, previews) is never stamped and always runs, the
    /// way `executeNewLeagueYear` treats one.
    ///
    /// Returns whether this call was the one that ran it.
    @discardableResult
    static func simulateRemainingFAOnce(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID?,
        modelContext: ModelContext,
        capMode: CapMode = .simple,
        career: Career?
    ) -> Bool {
        if let career {
            // `>=` and not `!=`, matching `executeNewLeagueYear`: the year only
            // moves at the roster-cuts → regular-season transition, so a stamp
            // at or past `currentSeason` means this league year is already done.
            guard career.lastBulkMarketSeason < career.currentSeason else { return false }
            career.lastBulkMarketSeason = career.currentSeason
        }
        simulateRemainingFA(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: playerTeamID,
            modelContext: modelContext,
            capMode: capMode,
            season: career?.currentSeason ?? 0
        )
        return true
    }

    // MARK: - One signing door for the interactive path (task #93 F7)

    /// Sign a free agent to an AI club during the PLAYED free-agent rounds.
    ///
    /// `FAWeeklyView` used `ContractEngine.signPlayerSimple` directly in both of
    /// its AI-vs-AI paths, which meant a real career's market ran on rules the
    /// bulk market does not use:
    ///
    /// * **Cap mode was ignored.** `signPlayerSimple` always debits
    ///   `currentCapUsage`, so a `.sandbox` league — where the cap is switched
    ///   off by definition — still had its AI clubs charged for every signing,
    ///   and `.realistic` never got a `Contract` row for one.
    /// * **The reserve was ignored.** `generateAIOffers` will not BID above
    ///   `capReservePercent`, and then the signing that resolved the bid spent
    ///   straight through it: the whole point of task #27's reserve is that the
    ///   draft class and the in-season refill still have to be paid for, and
    ///   half a budget is not a budget.
    ///
    /// Returns whether the deal was written, so a caller can leave the man on
    /// the market when his suitor turns out not to be able to afford him.
    @discardableResult
    static func signFreeAgentAI(
        player: Player,
        team: Team,
        years: Int,
        salary: Int,
        capMode: CapMode,
        modelContext: ModelContext
    ) -> Bool {
        if capMode != .sandbox {
            let reserve = Int(Double(team.salaryCap) * capReserve(forTeam: team.id))
            guard team.availableCap - reserve >= salary else { return false }
        }
        signFreeAgent(
            player: player,
            team: team,
            years: max(1, years),
            salary: salary,
            capMode: capMode,
            modelContext: modelContext
        )
        ChurnDiag.record(ChurnDiag.faSign, player)
        return true
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

        /// The best rating this club has in `position`'s GROUP — i.e. what it
        /// would still be able to put on the field there (task #98).
        ///
        /// The group and not the exact position, matching `need` above: a club
        /// with three good guards is not thin at right guard, and grading a
        /// veteran against the man who happens to share his exact slot label
        /// would read every interior lineman as irreplaceable.
        func bestOverall(teamID: UUID, position: Position) -> Int {
            let (groupPositions, _) = FreeAgencyEngine.positionGroupInfo(for: position)
            guard let teamMap = byTeam[teamID] else { return 0 }
            var best = 0
            for groupPosition in groupPositions {
                if let entry = teamMap[groupPosition] { best = max(best, entry.best) }
            }
            return best
        }

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
            // Task #92b — "no QB1" and "no QB2" were the same answer.
            if FreeAgencyEngine.isUnmannedStarterSlot(position: position, bestOVR: bestOVR) {
                return .critical
            }
            let deficit = idealCount - count
            if deficit >= 2 || (deficit >= 1 && bestOVR < 70) { return .high }
            if deficit >= 1 || bestOVR < 75 { return .moderate }
            return .none
        }

        /// The club's most valuable UNMANNED position group, or `nil` if it has
        /// none (task #92c). This is the hole the per-club reserve is held for:
        /// one per club, critical only, ranked by the same positional-value
        /// tiers the draft board uses so a missing quarterback outranks a
        /// missing kicker.
        ///
        /// Deterministic on ties (`rawValue`), so two identical rosters reserve
        /// for the same hole.
        func topCriticalHole(teamID: UUID) -> Position? {
            var best: (position: Position, priority: Double)?
            for position in Position.allCases {
                guard need(teamID: teamID, position: position) == .critical else { continue }
                let priority = FreeAgencyEngine.holePriority(position)
                if let current = best {
                    guard priority > current.priority
                        || (priority == current.priority && position.rawValue < current.position.rawValue)
                    else { continue }
                }
                best = (position, priority)
            }
            return best?.position
        }
    }

    // MARK: - Starter slots vs depth slots (task #92b)

    /// The OVR the best man in a group has to reach before the club stops
    /// treating the group as UNMANNED rather than merely thin.
    ///
    /// `RosterNeedIndex` counted bodies against an ideal depth chart and then
    /// graded quality only as a tie-breaker, so "we have two quarterbacks and
    /// the better of them is a 66" read as `.moderate` — the same answer as
    /// "we have three good receivers and would like a fourth". A club with no
    /// starter at a premium position is not shopping for depth, and 70 is the
    /// line the rest of this file already uses for starter quality (the `.high`
    /// branch below, `ownCoreAppealFloor`'s 72 after the age discount).
    static let starterQualityOVR = 70

    /// Position groups where "our best man is not a starter" is a crisis rather
    /// than a depth problem.
    ///
    /// The premium tier of `DraftEngine`'s own positional-value table:
    /// {QB, DE, CB, WR, LT}. Nothing wider.
    ///
    /// It was briefly widened to the whole offensive line "because
    /// ``positionGroupInfo`` scores all five line spots as one group and the
    /// left tackle is the one that makes the group premium" — which is the
    /// opposite of what that reasoning implies. The group's `bestOVR` is the
    /// same number at all five spots, so a club whose best lineman is a 69 read
    /// `.critical` at LT **and** LG **and** C **and** RG **and** RT
    /// simultaneously: `needWeight` 3.0 and `needMultiplier` 1.3-1.5 five times
    /// over, in `RosterNeedIndex.need`, in `assessPositionNeed` (and therefore
    /// in `TamperingRumorEngine`) and in `resignAIOwnCore`. Listing LT alone
    /// makes the group premium exactly once, which is what "the left tackle is
    /// what makes the group premium" actually means.
    static func isPremiumGroup(_ position: Position) -> Bool {
        switch position {
        case .QB, .WR, .DE, .CB, .LT: return true
        default: return false
        }
    }

    /// Whether a group's best man leaves a starter slot genuinely unfilled.
    /// Shared by ``RosterNeedIndex/need(teamID:position:)`` and
    /// ``assessPositionNeed(team:position:allPlayers:)`` so the two cannot
    /// drift apart.
    static func isUnmannedStarterSlot(position: Position, bestOVR: Int) -> Bool {
        bestOVR < starterQualityOVR && isPremiumGroup(position)
    }

    /// How badly a club wants THIS hole filled first, mirroring the positional
    /// weights `DraftEngine.teamNeedComponents` ranks its deficits by.
    static func holePriority(_ position: Position) -> Double {
        switch position {
        case .QB, .DE, .CB, .WR, .LT:           return 1.0
        case .DT, .OLB, .MLB, .FS, .SS, .TE:    return 0.8
        case .RB, .RG, .LG, .C, .RT, .FB:       return 0.6
        case .K, .P, .LS, .H:                   return 0.3
        }
    }

    /// The canonical member of a position's depth group — the key everything
    /// that reasons about GROUPS (not exact positions) is filed under.
    static func positionGroupKey(for position: Position) -> Position {
        positionGroupInfo(for: position).positions.first ?? position
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

    /// The reserve THIS club holds back — a taste, not a rail (D2c).
    ///
    /// ``capReservePercent`` is the league-average bill, and it was applied
    /// identically to all 32 clubs, which is why no AI club could ever be short
    /// of money in November: every one of them had budgeted for the same winter
    /// with the same discipline. Real front offices differ on exactly this. The
    /// analytics GM keeps powder dry and is the club still able to absorb a
    /// deadline salary; the aggressive one spends to the edge in March and finds
    /// out in December what that cost.
    ///
    /// The floor of the band is deliberate. The two bills the market does not
    /// pay — the rookie class and the in-season refill — measure **6.6 % of cap**
    /// between them, so a club reserving 8 % has almost nothing between itself
    /// and trouble, and one reserving 18 % has a real cushion. An aggressive club
    /// SHOULD occasionally end its year in the red; that is the point, and it is
    /// the mechanism that puts a good player on the market in March.
    ///
    /// The mean across the four archetypes is ~0.1375, a shade under the 0.15
    /// rail, so the league runs slightly tighter overall — the direction D2 wants
    /// the cap to move.
    static func capReserve(forTeam teamID: UUID) -> Double {
        switch TradeValueEngine.GMPersona.forTeam(id: teamID).archetype {
        case .analytics:  return 0.18
        case .balanced:   return 0.15
        case .oldSchool:  return 0.14
        case .aggressive: return 0.08
        }
    }

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
    /// sign 30-year-old All-Stars, they just do not sign them ahead of a
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
    /// How much one OVR point of misread moves a club's APPETITE in the bulk
    /// market's weighted pick. Larger than the money knob because a weight is a
    /// relative quantity competing against need and stance, and a 3 % nudge there
    /// would be invisible.
    static let perceptionWantPerOVR = 0.06

    /// Bound on the same, so a fat-tail read tilts the pick rather than deciding
    /// it outright. Need still outranks taste (`marketPersonalityLeanCap`'s rule).
    static let perceptionWantSwingCap = 0.35

    /// How much one OVR point of misread moves a club's bid. 0.03 = a 2-point
    /// misread is worth ~6 % on the price — enough to decide a contested signing,
    /// small enough that the market does not become noise.
    static let perceptionPricePerOVR = 0.03

    /// Hard bound on the fog's effect on money, so a fat-tail read (±6-10 OVR)
    /// becomes a bad decision rather than an absurd one. ±20 %.
    static let perceptionPriceSwingCap = 0.20

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

    // MARK: - Need as a WEIGHT, not just a sort key (task #89)

    /// How much more likely a club is to win a free agent because it needs the
    /// position, per level of the ``RosterNeedIndex`` depth ladder.
    ///
    /// ## Why weights and not a filter
    ///
    /// Need used to be an ORDERING term only: `simulateAIFreeAgency` split the
    /// eligible clubs into `needy` (rank > 0) and `rest` (rank 0), put the needy
    /// first, and then took the first `marketInterest` of the concatenation as
    /// the shortlist — from which the winner was drawn (near-)uniformly. Two
    /// consequences, both measured in the audit:
    ///
    /// * A club with a `.none` at the position was still fully eligible. When a
    ///   position is well stocked LEAGUE-wide — which is the normal case for WR,
    ///   CB and DE — `needy` is shorter than `marketInterest`, `rest` fills the
    ///   rest of the shortlist, and `rest` is ordered by **cap space**. So the
    ///   richest clubs signed the surplus, *including the club that already had
    ///   eight receivers*.
    /// * Inside the shortlist, a `.critical` hole and a `.moderate` one were the
    ///   same coin flip.
    ///
    /// Making these weights on the existing `weightedPick` fixes both without
    /// changing WHO IS ELIGIBLE — shortlist membership is untouched, so task
    /// #53's churn calibration (`expire`/`faSign`/`washout` counts and their age
    /// and OVR means) holds and only the destination moves.
    ///
    /// The contract COUNT is approximately preserved rather than invariant, and
    /// the distinction is worth stating: eligibility is evaluated against live
    /// cap and roster state, so changing which club wins agent #1 changes which
    /// clubs are still eligible by agent #40. The number of deals a league year
    /// writes moves by a handful, not by a wave.
    static func needWeight(_ level: PositionNeedLevel) -> Double {
        switch level {
        case .critical: return 3.0
        case .high:     return 2.0
        case .moderate: return 1.3
        case .none:     return 0.25
        }
    }

    /// Extra pull when the position is one of the club's five biggest holes on
    /// `DraftEngine.teamNeedDeficits` — the same roster evidence the AI drafts
    /// and refills from, so a club chases the same positions in March that it
    /// will chase in April instead of running two unrelated need models.
    ///
    /// Deliberately small and bounded: the deficit board says "this hole
    /// matters" (it still ranks by positional value among real holes), while the
    /// depth ladder above says "this hole is deep". One nudge, never an override.
    ///
    /// It reads `teamNeedDeficits` rather than `topTeamNeeds` because a bonus is
    /// only a bonus if somebody does not get it: `topTeamNeeds` hands back
    /// {QB, DE, CB, WR, LT} for every full roster in the league, so ×1.5 on it
    /// was a constant applied to all 32 clubs at once — arithmetically invisible
    /// in the `weightedPick` it feeds, and a real bias everywhere else it was
    /// read as "this club needs this position".
    static let topNeedBonus = 1.5

    // MARK: - Stance and persona reach the market (task #91)

    /// The widest lean any single personality term may put on a club's pull in
    /// free agency, and its reciprocal on the way down.
    ///
    /// **What it actually does today.** `TeamStance.incomingAgeMultiplier`
    /// spans 0.72…1.10 (`TradeValueEngine.incomingAgeMultiplier`), so against
    /// the `[1/1.30, 1.30] = [0.769, 1.30]` band this clamp bites exactly one
    /// branch — a rebuilding club looking at a 31-plus veteran, 0.72 → 0.769 —
    /// and the upper bound is unreachable. It is a RAIL, not a working knob,
    /// and the doc used to claim otherwise ("a rebuilding club simply stops
    /// appearing in the league at all" describes a failure the raw span never
    /// produced).
    ///
    /// **Why the rail stays.** That table was written for a TRADE, where it
    /// prices one asset against a pick chart and a 28 % discount is a
    /// negotiating position. Here it multiplies a roulette-wheel weight that
    /// already carries `needWeight` (0.25…3.0), `topNeedBonus` (1.5×), market
    /// appeal (1.35×) and the settlement lean (1.43×) — a compounded ~6.7 : 1
    /// spread across a shortlist. Widening the trade-side table for trade
    /// reasons must not silently widen that, and 1.30 is a shade under
    /// `needWeight`'s smallest real step, which is the property that matters:
    /// need still outranks taste.
    static let marketPersonalityLeanCap = 1.30

    /// `TeamStance.incomingAgeMultiplier` bounded to ``marketPersonalityLeanCap``
    /// in both directions.
    static func boundedStanceLean(_ multiplier: Double) -> Double {
        min(marketPersonalityLeanCap, max(1.0 / marketPersonalityLeanCap, multiplier))
    }

    /// Where in the `[floor, ask]` band a GM settles, as a bias on the uniform
    /// draw the AI-vs-AI market has always used.
    ///
    /// The settlement was `floor + (ask − floor) × U(0,1)` for all 32 clubs —
    /// the same negotiator everywhere, in a league that already models four
    /// distinct GM archetypes with their own asking premiums, concession rates
    /// and patience for the user's phone calls. Applied as an exponent,
    /// `U^(1/lean)`, so it is a genuine shift of the whole distribution rather
    /// than a clamp: the draw still spans the full band, the mass just moves.
    ///
    /// Bounded by construction. `E[U^(1/lean)] = lean / (1 + lean)`, so the
    /// table below moves the average settlement from 0.500 of the band to
    /// 0.444 (analytics) … 0.556 (aggressive) — a 1.25× spread end to end,
    /// inside ``marketPersonalityLeanCap`` and far inside the ±15 % the agent's
    /// own floor and ask already move between two players.
    ///
    /// The ordering is the trade market's, so a GM negotiates like himself in
    /// both rooms: the aggressive GM "chases stars, pays a premium" and settles
    /// high; the analytics GM prices everything below the chart and settles
    /// low; the old-school GM pays the going rate.
    static func settlementLean(_ archetype: TradeValueEngine.GMArchetype) -> Double {
        switch archetype {
        case .aggressive: return 1.25
        case .oldSchool:  return 1.08
        case .balanced:   return 1.00
        case .analytics:  return 0.80
        }
    }

    // MARK: - Contract LENGTH is a club decision too (task #89)

    /// The longest deal an AI club will write for a player of this age.
    ///
    /// `generateFreeAgentMarket` already bands what the PLAYER wants by his
    /// position's peak window, but the club had no say at all — the market
    /// signed `agent.desiredYears` verbatim. `Position.peakAgeRange` runs to 35
    /// for a quarterback and 38 for a kicker, so "inside his peak" bought a
    /// 35-year-old the same 2-4 year deal a 27-year-old got, at market money,
    /// on books that then had to carry him to 39. Clubs buy years from young
    /// men and rent seasons from old ones.
    ///
    /// Applied as `min(desiredYears, ceiling)` so it can only ever shorten a
    /// deal: nobody is handed more term than he asked for.
    static func contractYearsCeiling(age: Int) -> Int {
        switch age {
        case ..<27:   return 5
        case 27...28: return 4
        case 29...30: return 3
        case 31...32: return 2
        default:      return 1
        }
    }

    // MARK: - Own-core priority (task #89)

    /// Players one AI club may keep off the market per league year.
    ///
    /// ## Why this exists: the league had no incumbency at all
    ///
    /// `FreeAgencyStep` opens with `finalPush` — "re-sign your own expiring
    /// players" — and that step is a **user-only screen** (`FinalPushView`).
    /// Nothing in `WeekAdvancer`, `FreeAgencyEngine` or `ContractEngine` ever
    /// extended an AI club's own player, so `executeNewLeagueYear`'s expiry loop
    /// stripped every expiring contract in all 32 organisations to
    /// `teamID = nil` and an 88-OVR franchise cornerstone hit the open market
    /// with exactly the same claim on his club as a stranger. It was the most
    /// player-favouring asymmetry left in the offseason, and it also meant the
    /// league a save *starts* with (whose cap sheet `LeagueGenerator` shapes
    /// with `earlyExtensionOverall`) is not the league it *becomes*.
    ///
    /// Bounded on purpose. Three per club is roughly a tenth of a typical
    /// expiring cohort, and a retention is 1:1 with a signing the market would
    /// otherwise have written for the same man (he is at the top of the pool by
    /// `marketAppeal` — that is the test below), so the churn funnel task #53
    /// calibrated moves a name from `faSign` to `resign` rather than changing
    /// how many players the league employs or how old they are.
    static let ownCoreRetentionsPerClub = 3

    /// `marketAppeal` a man must clear before his own club will pay to keep him
    /// — starter quality after the age discount. Below this the club is better
    /// off letting the market set his price and re-signing him there, which is
    /// what it already does.
    static let ownCoreAppealFloor = 72.0

    /// Appeal at which a club keeps a player REGARDLESS of positional need. You
    /// do not let a genuine star walk because the depth chart says the room is
    /// full.
    static let ownCoreStarAppeal = 80.0

    /// The incumbent's discount. Staying put is worth something — no move, no
    /// new playbook, no new city — and real re-signings land a few points under
    /// the open-market ask. Never below the agent's own floor.
    static let ownCoreHometownDiscount = 0.95

    // MARK: - The veteran door (task #98)

    /// Ageing starters one AI club may keep off the market per league year, on
    /// top of ``ownCoreRetentionsPerClub``.
    ///
    /// ## Why the core budget could not reach these men
    ///
    /// Every door back onto a roster ranks a player through an age discount, and
    /// all three of them saturate before a 33-year-old arrives:
    ///
    /// * ``ownCoreAppealFloor`` (72) is a floor on ``marketAppeal``, which docks
    ///   the full ``marketAgeDiscountCap`` (14) from age 30. A 33-year-old
    ///   therefore has to be an **86 OVR** to be worth a conversation with his
    ///   own club — roughly the top 40 players alive.
    /// * The open market sorts on the same appeal, so he is behind every
    ///   72-OVR 25-year-old in the pool.
    /// * `WeekAdvancer.refillAIRosters` sorts on `RosterValue.keepScore`, whose
    ///   age term was uncapped entirely until this same task.
    ///
    /// Measured over an 8-season `PERF_SMOKE_SEASONS` run the consequence is a
    /// 33+ share of **0.7-1.1 %** against a generator opening at 2.7 % and the
    /// `career` rig's ~3.1-3.2 % equilibrium: the league's opening veterans
    /// reach the market once and essentially none of them come back. The exit is
    /// not the retirement hazard (that pass is calibrated and its own gate is
    /// green); it is that nobody re-signs them, after which
    /// `PlayerRetirementEngine.washoutProbability` reads the silence correctly
    /// and removes them.
    ///
    /// ## Why a separate budget rather than a bigger one
    ///
    /// ``ownCoreRetentionsPerClub`` is already saturated — the measured league
    /// writes 2.5 retentions per club against a cap of 3 — so an age door added
    /// to the same budget would only DISPLACE a young star, and a displaced
    /// young star is fine: he is at the top of the pool by appeal and the market
    /// signs him within the hour. A displaced 33-year-old is gone for good.
    /// The two decisions are not competing for the same money in a real front
    /// office either: keeping your own ageing starter on a one-year deal is the
    /// most routine transaction in the league, not a franchise-defining one.
    ///
    /// Two per club is a ceiling, not a quota: the qualification below is
    /// genuinely narrow (he must still be the best man his club has at his
    /// position, and starter-quality in absolute terms), so most clubs will use
    /// one or none in a given year.
    static let ownCoreVeteranRetentionsPerClub = 2

    /// Age from which a man is judged on production instead of on the market's
    /// age discount. One year before `contractYearsCeiling` drops a club to
    /// two-year offers, which is where "how much has he declined" turns into
    /// "how many years are left".
    static let ownCoreVeteranAge = 31

    /// Overall a veteran must still hold for this door to open — starter
    /// quality with nothing subtracted for the calendar.
    ///
    /// Stated in raw OVR on purpose. The whole point of the door is that it does
    /// NOT read `marketAppeal`; running it through the same discount that closed
    /// the core door would reproduce the core door with a different number on it.
    /// 76 is comfortably above ``starterQualityOVR`` (70) so a club is keeping a
    /// man it would otherwise have to replace at market price, and comfortably
    /// below the 80+ band so the door is about ordinary good players rather than
    /// about stars (a star clears ``ownCoreStarAppeal`` and never reaches here).
    static let ownCoreVeteranOverallFloor = 76

    /// How close the club's next-best man at the position has to be before the
    /// veteran is treated as replaceable.
    ///
    /// The door asks "does this club have a successor", and a successor is not
    /// "somebody at the position" — it is somebody who can do the job. Four
    /// points is one tier of the roster: a club whose next man is within four of
    /// a 78-OVR veteran has a starter already and lets the 33-year-old walk,
    /// while a club whose next man is a 70 does not. Without a gap the test
    /// would be `bestOverall < player.overall`, which every expiring starter
    /// passes by construction (he IS the best man at his position, which is why
    /// `needIndex` is built with the expiring cohort removed) and the door would
    /// stop being narrow.
    static let ownCoreVeteranSuccessorGap = 4

    /// Let every AI club re-sign a bounded number of its own expiring core
    /// before the league year turns. Returns the number of deals written.
    ///
    /// Runs INSIDE `executeNewLeagueYear`, immediately before the expiry loop:
    /// a retained player's `contractYearsRemaining` is set to `years + 1`, so
    /// the decrement the loop is about to apply leaves him on exactly the deal
    /// that was agreed here and he never appears in `newFAs`.
    ///
    /// The user's own club is skipped — that is what `FinalPushView` is.
    ///
    /// - Parameter season: the league year being closed out
    ///   (`career.currentSeason`). Feeds the negotiation situation below, so a
    ///   stance an agent takes can expire the way it does on the user's screen.
    /// - Parameter capMode: `.sandbox` switches the budget off entirely, matching
    ///   `simulateAIFreeAgency`, which drops its cap filters in the same mode.
    @discardableResult
    static func resignAIOwnCore(
        allPlayers: [Player],
        allTeams: [Team],
        userTeamID: UUID?,
        season: Int = 0,
        capMode: CapMode = .simple
    ) -> Int {
        guard !allPlayers.isEmpty else { return 0 }

        // Expiring men by club, and the payroll that SURVIVES the rollover.
        // `team.currentCapUsage` still carries every contract that is about to
        // run out, so it is the wrong number to budget a retention against —
        // the honest one is what the club will still owe once the loop below
        // has done its work.
        var expiringByTeam: [UUID: [Player]] = [:]
        var survivingPayrollByTeam: [UUID: Int] = [:]
        var rosterByTeam: [UUID: [Player]] = [:]
        var expiringIDs: Set<UUID> = []
        for player in allPlayers {
            guard let teamID = player.teamID, teamID != userTeamID, !player.isRetired else { continue }
            rosterByTeam[teamID, default: []].append(player)
            if player.contractYearsRemaining > 1 {
                survivingPayrollByTeam[teamID, default: 0] += player.annualSalary
            }
            guard player.contractYearsRemaining == 1,
                  !player.isFranchiseTagged,
                  !player.isOnPracticeSquad else { continue }
            expiringByTeam[teamID, default: []].append(player)
            expiringIDs.insert(player.id)
        }

        // **The depth chart WITHOUT the men under discussion.** Built from
        // `allPlayers` it counted the expiring player himself, and since he is by
        // construction the best man at his position on this list (the loop below
        // works down from the top by `marketAppeal`), his own OVR was the
        // `bestOVR` the ladder read — so the club looked at a room whose only
        // starter is walking out of the door and concluded it had no need there.
        // A 78-appeal starter was therefore dropped unless he cleared
        // `ownCoreStarAppeal`; the club's own quality was the reason it let him
        // go. The question a front office is actually asking in March is "what
        // does this roster look like if he leaves", which is this index.
        //
        // Retentions are added back as they land, so a club that has just kept
        // its left tackle does not read the room as empty for the next one.
        var needIndex = RosterNeedIndex(
            allPlayers: allPlayers.filter { !expiringIDs.contains($0.id) }
        )

        var retained = 0
        for team in allTeams where team.id != userTeamID {
            guard let expiring = expiringByTeam[team.id], !expiring.isEmpty else { continue }

            // The club's genuine HOLES, not the league's positional-value table.
            // `DraftEngine.topTeamNeeds` returns {QB, DE, CB, WR, LT} for every
            // full roster in the league (see `teamNeedDeficits`), so reading it
            // here meant "we need this position" was automatically true for any
            // quarterback, end, corner, receiver or left tackle — a positional
            // bias wearing a need model's clothes, on the one decision that
            // decides whether a club keeps its own man.
            let topNeeds = Set(
                DraftEngine.teamNeedDeficits(roster: rosterByTeam[team.id] ?? [], limit: 5)
            )
            // Spendable = cap minus the market's reserve minus what is already
            // committed for next league year. Deliberately measured against the
            // PRE-growth cap (growth is applied further down `executeNewLeagueYear`),
            // which makes the budget conservative rather than optimistic.
            //
            // Sandbox has no budget at all, exactly as `simulateAIFreeAgency`
            // signs without a cap filter there: half a cap model is worse than
            // none, because it would let the user's league spend freely while
            // every AI club still had to balance its books.
            var room = Int(Double(team.salaryCap) * (1.0 - capReserve(forTeam: team.id)))
                - (survivingPayrollByTeam[team.id] ?? 0)
            var signed = 0
            // Task #98 — men this club has already kept, so the veteran pass
            // below cannot re-sign somebody the core pass just signed.
            var keptIDs: Set<UUID> = []

            /// One agreed retention: price it against the incumbent demand model
            /// and write the deal. Returns false when the man refuses, the price
            /// is nonsense, or the club cannot afford him.
            ///
            /// Shared by both passes so a veteran retention costs the club
            /// exactly what a core retention costs — the door decides WHO is
            /// asked, never what the answer is priced at.
            func retain(_ player: Player) -> Bool {
                // What the club has to negotiate against: the season it just
                // played. The demand model reads a record — a losing building
                // pays a premium, a contender gets a discount, and the
                // ring-chaser's exit condition is literally "become a
                // contender". The default `.neutral` this used to take made
                // every AI club in the league look identical to every agent in
                // it. `team.wins`/`losses` are still the completed season here;
                // the rollover runs months before `startNewSeason` resets them.
                // Built per player because half of a situation is a fact about
                // the MAN (his career year, his prove-it bet), exactly as
                // `FinalPushView.reSignSituation(for:)` builds it.
                let situation = ContractNegotiationEngine.situation(
                    for: player,
                    season: season,
                    teamWins: team.wins,
                    teamLosses: team.losses,
                    weeksPlayed: team.wins + team.losses
                )
                // The SAME call `FinalPushView` makes for the user's own
                // expiring players: `.extend`, because this is an incumbent and
                // not a stranger, with the club's real season attached. That is
                // what puts the refusal model on the table for the other 31
                // clubs — `refusalVerdict` is an extension-only gate, so under
                // the old `.freeAgent` demand `neverSigns` was structurally false
                // and no AI club could ever be turned down by anybody. It also
                // prices an incumbent like one: `situationBreakdown`'s
                // `isOwnClub` is what makes the loyalty discount and a captain's
                // full archetype discount reach the ask.
                let demand = ContractNegotiationEngine.demand(
                    player: player,
                    negotiationType: .extend,
                    salaryCap: team.salaryCap,
                    situation: situation
                )
                // A man who will not re-sign at any price is not a negotiation.
                // The rarity budgets live inside `ContractNegotiationEngine`; the
                // club simply respects the answer and lets him reach the market,
                // where a contender can sign him.
                guard !demand.isRefusing else { return false }

                let price = max(
                    min(demand.askAmount, Int(Double(demand.askAmount) * ownCoreHometownDiscount)),
                    demand.floorAmount
                )
                guard price > 0 else { return false }
                if capMode != .sandbox {
                    guard price <= room else { return false }
                }

                let years = max(1, min(4, contractYearsCeiling(age: player.age)))
                // +1 because the expiry loop below decrements every contract.
                player.contractYearsRemaining = years + 1
                player.annualSalary = price
                room -= price
                retained += 1
                keptIDs.insert(player.id)
                needIndex.add(position: player.position, overall: player.overall, to: team.id)
                ChurnDiag.record(ChurnDiag.resign, player)
                return true
            }

            // --- Pass 1: the core, ranked by market appeal (task #89) --------
            for player in expiring.sorted(by: { marketAppeal($0) > marketAppeal($1) }) {
                guard signed < ownCoreRetentionsPerClub else { break }
                let appeal = marketAppeal(player)
                // Sorted descending — once one man is under the floor, so is
                // everyone after him.
                guard appeal >= ownCoreAppealFloor else { break }

                let wanted = needIndex.need(teamID: team.id, position: player.position) != .none
                    || topNeeds.contains(player.position)
                guard wanted || appeal >= ownCoreStarAppeal else { continue }

                if retain(player) { signed += 1 }
            }

            // --- Pass 2: the veteran door (task #98) -------------------------
            //
            // Judged on production and on the hole he would leave, with the
            // market's age discount deliberately not applied — see
            // `ownCoreVeteranRetentionsPerClub` for why the pass-1 budget could
            // never reach these men.
            //
            // The "would leave" test is what keeps this narrow: the club looks at
            // the room WITHOUT him (`needIndex` was built with every expiring
            // player removed, and pass 1's retentions have been added back), and
            // he only qualifies if it has nobody at his position who is within
            // `ownCoreVeteranSuccessorGap` of him. A club with a ready successor
            // lets the 33-year-old walk, which is what a real front office does
            // and is the whole reason this is not simply "keep every old
            // starter".
            var vetSigned = 0
            for player in expiring.sorted(by: { $0.overall > $1.overall }) {
                guard vetSigned < ownCoreVeteranRetentionsPerClub else { break }
                guard !keptIDs.contains(player.id) else { continue }
                guard player.age >= ownCoreVeteranAge else { continue }
                // Sorted descending on overall — once one man is under the floor,
                // so is everyone after him.
                guard player.overall >= ownCoreVeteranOverallFloor else { break }
                guard needIndex.bestOverall(teamID: team.id, position: player.position)
                        < player.overall - ownCoreVeteranSuccessorGap else { continue }

                if retain(player) { vetSigned += 1 }
            }
        }
        return retained
    }

    // MARK: - Fifth-Year Option (task #90)

    /// The option's price as a share of the franchise tag for the man's
    /// position. The real CBA prices the fifth year off a positional average of
    /// the top salaries (top-3 or top-20 depending on where he was taken and
    /// what he has achieved); this game already computes exactly one such
    /// number — ``ContractEngine/franchiseTagValue(position:topSalaries:)``, the
    /// top-5 average — so the option is expressed as a discount on it rather
    /// than as a second, parallel positional wage table that would immediately
    /// drift away from the first.
    ///
    /// 0.80 puts a first-round fifth year meaningfully under the tag (that is
    /// the whole reason a club values the option) while staying well clear of
    /// the rookie slot it replaces, so picking a man up is a real commitment.
    static let fifthYearOptionTagShare = 0.80

    /// `marketAppeal` at which an AI club picks the option up regardless of
    /// where his raw overall currently sits — the young riser who has not
    /// arrived yet but plainly will. Same scale as ``ownCoreAppealFloor``.
    ///
    /// ## Task #101 — why 74 was not a floor at all
    ///
    /// Measured over the balance rig (`tools/balance-harness` `career` pipeline,
    /// 8 leagues x 30 seasons, 5 364 candidates): the option was exercised on
    /// **95.7 %** of first-rounders reaching the window, against a design intent
    /// that says "MOST of round 1 is below both doors". The two seeds of the
    /// 8-season app analysis measured the same thing from the other end at ~81 %.
    ///
    /// The reason is arithmetic, not judgement. A man in this window is 24 years
    /// old (mean 24.3), so ``marketAgeDiscountFrom``'s 25-year threshold has not
    /// touched him yet, and he is three years pro, so ``marketUpsidePremium``
    /// credits him 0.45 of his remaining ceiling. The measured cohort averages
    /// OVR 74.1 against a true potential of 92.8 — eighteen points of headroom —
    /// so `marketAppeal` hands him **+8.4 points on average** and the cohort's
    /// mean appeal is 81.9. A floor of 74 sits a full standard deviation below
    /// the middle of the population it is supposed to filter.
    ///
    /// 80 is the same statement about the same man, priced honestly: the option
    /// costs 80 % of the franchise tag, i.e. starter money, so the young riser
    /// has to project as a starter. In appeal units 80 is "OVR 74 with a 87
    /// ceiling", "OVR 78 with an 82 ceiling", or "an 80 today" — and it puts the
    /// rig at 66 % and, netting out the user-club auto-decline and the
    /// affordability test the rig does not model, the app in the intended
    /// 50-60 % band. Re-measure with `PERF_SMOKE_SEASONS`; this constant is the
    /// single knob.
    static let fifthYearOptionAppealFloor = 80.0

    /// Overall at which an AI club picks the option up on production alone: a
    /// starter the club would have to replace at market price.
    ///
    /// Unchanged by task #101, but note what the pair does: `marketAppeal` never
    /// SUBTRACTS anything from a 24-year-old (the age discount starts at 25) and
    /// only ever adds the upside premium, so for this cohort `appeal >= overall`
    /// always holds. Door B is therefore only reachable by a man door A missed
    /// when this floor is BELOW the appeal floor — which is why 74/78 made door
    /// B pure dead code (its 26.8 % of the cohort was a strict subset of door
    /// A's 95.7 %) and why 80/78 gives it a narrow live band again: the finished
    /// 78-79 with no headroom left, and the rare 26-year-old in the window.
    static let fifthYearOptionOverallFloor = 78

    /// Rookie-deal seasons behind a man when the option question is asked. See
    /// ``isFifthYearOptionWindow`` for the calendar trace.
    static let fifthYearOptionYearsPro = 3

    /// Contract years still on the sheet when the question is asked, read
    /// BEFORE ``executeNewLeagueYear``'s expiry decrement. Two here becomes one
    /// after the decrement, i.e. he is entering the final year of the deal.
    static let fifthYearOptionContractYears = 2

    /// Is this man standing in his fifth-year-option window RIGHT NOW?
    ///
    /// "Now" is unambiguously **before this league year's expiry decrement**:
    /// both callers — `FinalPushView` (the offseason re-sign screen, which runs
    /// at `FreeAgencyStep.finalPush`, ahead of the rollover) and
    /// ``settleFifthYearOptions`` (which runs inside ``executeNewLeagueYear``
    /// immediately before the expiry loop) — read the roster in that state, and
    /// pricing a decision against a number that means two different things
    /// depending on who is asking is exactly the split-brain task #89 spent its
    /// life closing.
    ///
    /// ## Why these three numbers, and why the window fires exactly once
    ///
    /// Trace one first-rounder taken in the draft phase of the offseason that
    /// closes season `S` (`career.currentSeason == S` there; the year does not
    /// move until the roster-cuts → regular-season transition months later).
    /// `convertToPlayer` gives him `yearsPro = 0`, `contractYearsRemaining = 4`
    /// (``DraftEngine/rookieContract(pickNumber:salaryCap:)``).
    ///
    /// | moment                            | yearsPro | contract years |
    /// |-----------------------------------|----------|----------------|
    /// | drafted (offseason `S`)           | 0        | 4              |
    /// | training camp `S` (age regression)| 1        | 4              |
    /// | plays season `S+1`                | 1        | 4              |
    /// | **rollover, offseason `S+1`**     | 1        | 4 → 3          |
    /// | training camp `S+1`               | 2        | 3              |
    /// | plays season `S+2`                | 2        | 3              |
    /// | **rollover, offseason `S+2`**     | 2        | 3 → 2          |
    /// | training camp `S+2`               | 3        | 2              |
    /// | plays season `S+3`                | 3        | 2              |
    /// | **offseason `S+3` — THE WINDOW**  | **3**    | **2** → 1      |
    /// | plays season `S+4` (year 4)       | 4        | 1              |
    /// | rollover, offseason `S+4`         | 4        | 1 → 0 (market) |
    ///
    /// `yearsPro` only ever moves at training camp (`applyAgeRegression`, the
    /// single increment in the app), which is four phases AFTER free agency —
    /// so it is constant across a whole offseason and is a stable name for
    /// "which offseason is this". `contractYearsRemaining` only ever moves at
    /// the rollover. The pair `(3, 2)` therefore holds in exactly one offseason
    /// of a four-year rookie deal, and that offseason is the one before his
    /// fourth and final season — the real fifth-year-option deadline. Every
    /// other rollover in the table above misses on one term or the other.
    ///
    /// `fifthYearDecided` is the belt to that braces: ``settleFifthYearOptions``
    /// stamps it on everyone still in the window at the rollover, so even a
    /// contract shape this trace does not anticipate can only be asked once.
    ///
    /// Eligibility is DERIVED (``Player/isFirstRoundPick``) rather than stamped,
    /// because `draftRound` is already written once at draft time and never
    /// mutated — a fourth boolean would just be a copy of it that could go
    /// stale. Known and accepted simplification: a former first-rounder who was
    /// cut and re-signed onto an unrelated two-year deal that happens to line up
    /// with `yearsPro == 3` reads as eligible. He is a former top-32 pick
    /// entering the last year of a deal, so his club getting an option on him is
    /// a small wrongness, not a broken one.
    static func isFifthYearOptionWindow(_ player: Player) -> Bool {
        guard player.isFirstRoundPick,
              !player.fifthYearDecided,
              !player.isRetired,
              !player.isFranchiseTagged,
              !player.isOnPracticeSquad,
              player.teamID != nil else { return false }
        return player.contractYearsRemaining == fifthYearOptionContractYears
            && player.yearsPro == fifthYearOptionYearsPro
    }

    /// Every live salary in the league, grouped by position — the input
    /// ``ContractEngine/franchiseTagValue(position:topSalaries:)`` averages its
    /// top five of. Computed ONCE per rollover (or once per screen load) because
    /// the alternative is a full sweep of ~1 700 players per candidate.
    static func positionSalaryTable(allPlayers: [Player]) -> [Position: [Int]] {
        var table: [Position: [Int]] = [:]
        for player in allPlayers where player.annualSalary > 0 {
            table[player.position, default: []].append(player.annualSalary)
        }
        return table
    }

    // MARK: - Franchise Tag Settlement (task #127)

    /// **The one place forward money becomes real money**, and the other half of
    /// the fix `ContractEngine.applyFranchiseTag` starts.
    ///
    /// Two kinds of promise are collected here since #186 — the franchise tag it
    /// was built for, and the deferred contract extension, whose money also binds
    /// a league year that had not opened when it was agreed. They share this
    /// function because they share the table and, critically, the single
    /// read-and-delete `consumeForward` call: two sweeps of one ledger is how a
    /// promise gets settled twice. They differ in exactly one thing, the contract
    /// clock, and `CommittedCapLedger.Reservation.kind` is what tells them apart —
    /// see the deferred branch in the body. Everything below describes the tag.
    ///
    /// The tag is decided in the offseason and binds the league year this
    /// function opens. Applying it therefore writes nothing to `annualSalary` and
    /// nothing to `Team.currentCapUsage` — it flags the man and books the number
    /// as a forward commitment in `CommittedCapLedger`. This is where that
    /// promise is collected: the man's expired deal is replaced by the one-year
    /// tag, on the books of the year that has just started.
    ///
    /// Runs INSIDE ``executeNewLeagueYear``; see the call site for why the
    /// position in the sequence is load-bearing three separate ways.
    ///
    /// **What each tagged man gets:**
    ///
    /// * `annualSalary = tag` — the number the user was quoted when he pressed
    ///   the button, not a re-derived one. Re-deriving would be cheap (the
    ///   position salary table is right there) but it would let the charge drift
    ///   away from the quote as the rest of the offseason moved salaries around,
    ///   and a tag that costs more than the screen said is precisely the class of
    ///   dishonesty #127 is about. The re-derivation survives only as the
    ///   fallback for a row that is missing — a save written before this table
    ///   existed, or a harness run with no career to scope `UserDefaults` by.
    /// * `contractYearsRemaining = 1` — one year, and only one. The expiry loop
    ///   below skips `isFranchiseTagged` rows, so this survives the rollover
    ///   intact and ticks to 0 at the NEXT one, which puts him on the market a
    ///   year later exactly as a tag should.
    /// * the restructure receipt cleared, uncharged. The old deal is over; its
    ///   unpaid proration accelerates into the league year that just closed, and
    ///   the cap true-up a few lines down rebuilds usage from rostered salaries
    ///   — so it ages off with that year's dead money, which is the same
    ///   treatment the expiry loop gives a contract that simply runs out.
    ///
    /// **Orphans are dropped, not settled.** `consumeForward` returns every row
    /// binding at or before this year and deletes the lot; a row whose player has
    /// since retired, been cut or had his flag cleared by another engine simply
    /// finds no match here and disappears. That is the leak defence — nothing
    /// carries a stale tag into a second league year.
    ///
    /// Returns how many tags were settled (0 = nobody was tagged).
    @discardableResult
    ///
    /// - Parameter contractsByPlayer: the save's `Contract` rows, so a settled
    ///   deferred extension can be written onto the one it replaces (see
    ///   ``settleDeferredContract(row:player:teamID:contract:)``). Empty is the
    ///   simple/sandbox shape and costs nothing: those modes keep no rows.
    static func settleFranchiseTags(
        allPlayers: [Player],
        allTeams: [Team],
        career: Career?,
        contractsByPlayer: [UUID: Contract] = [:]
    ) -> Int {
        guard let career else { return 0 }

        // The year this rollover OPENS. `currentSeason` does not move across the
        // offseason (see `executeNewLeagueYear`'s doc), so the tag applied during
        // it was stamped `currentSeason + 1` and this is the same number.
        let bindingSeason = career.currentSeason + 1
        let due = CommittedCapLedger.consumeForward(
            careerID: career.id,
            bindingSeason: bindingSeason
        )

        // Belt to the braces: a tagged man with no row (pre-#127 save, or a
        // sandbox save whose $0 row was written before the ledger existed) still
        // has to come out of this function with a contract, or the expiry loop
        // would skip him and the true-up would carry the OLD salary into the new
        // year — the very bug in mirror image.
        let tagged = allPlayers.filter { $0.isFranchiseTagged && $0.teamID != nil && !$0.isRetired }
        guard !due.isEmpty || !tagged.isEmpty else { return 0 }

        // #186 — the OTHER thing this table now holds.
        //
        // A contract extension signed for a man who is still under contract does
        // not charge the open league year; `ContractEngine.applyNegotiatedDeal`
        // parks it here, stamped with the season the new money starts, and this
        // is the rollover that opens it. Settled in the same pass and off the
        // same `consumeForward` because read-and-delete must not be split: two
        // sweeps of one table is how a promise gets settled twice.
        //
        // What a deferred deal needs is exactly HALF of what a tag needs, which
        // is why the row carries a kind. The salary is written — the true-up a
        // few lines down sums `annualSalary`, so this is the moment the new rate
        // goes on the books. The CLOCK is not: `contractYearsRemaining` was
        // written the day the deal was signed and has been ticking down the old
        // deal's years ever since (#89 — one clock, one tick per rollover), so
        // touching it here would either erase the extension or hand out years
        // nobody negotiated. The restructure receipt IS cleared, for the reason
        // the tag branch clears it: the deal that receipt belonged to is the one
        // that just ran out.
        var deferredSettled = 0
        for row in due where row.forwardKind == .deferredDeal {
            guard let player = allPlayers.first(where: { $0.id == row.playerID }),
                  let teamID = player.teamID,
                  !player.isRetired,
                  player.contractYearsRemaining > 0
            else { continue }
            player.annualSalary = row.annualCapHit
            player.restructureReliefK = 0
            player.restructureProrationK = 0
            player.restructureCarryYears = 0
            settleDeferredContract(
                row: row,
                teamID: teamID,
                contract: contractsByPlayer[row.playerID]
            )
            deferredSettled += 1
        }

        // Tag rows only. A deferred deal's number is not a tag quote and must
        // never become one for a man who happens to be carrying a flag as well.
        var quoteByPlayer: [UUID: Int] = [:]
        for row in due where row.forwardKind == .franchiseTag {
            quoteByPlayer[row.playerID] = row.annualCapHit
        }

        // Only built when somebody actually needs the fallback — a full sweep of
        // ~1 700 players is not worth doing for the overwhelmingly common case
        // where every tag has its quote.
        var salaryTable: [Position: [Int]]?
        var capByTeam: [UUID: Int] = [:]
        for team in allTeams { capByTeam[team.id] = team.salaryCap }

        var settled = 0
        for player in tagged {
            let tag: Int
            if let quoted = quoteByPlayer[player.id] {
                tag = quoted
            } else {
                if salaryTable == nil { salaryTable = positionSalaryTable(allPlayers: allPlayers) }
                // The PRE-growth cap: league-year growth is applied further down
                // `executeNewLeagueYear`, so this is the same cap the tag screen
                // floored its quote against.
                tag = ContractEngine.franchiseTagValue(
                    position: player.position,
                    topSalaries: salaryTable?[player.position] ?? [],
                    capMode: career.capMode,
                    salaryCap: player.teamID.flatMap { capByTeam[$0] } ?? ContractEngine.openingSalaryCap
                )
            }

            player.annualSalary = tag
            player.contractYearsRemaining = 1
            // The one piece of state that outlives the flag. `executeNewLeagueYear`
            // clears `isFranchiseTagged` a few dozen lines below — it has to, or
            // the expiry loop would skip him forever — and from that moment
            // nothing else in the save says this man is playing a tag year. The
            // tag-and-extend shape is planned off this stamp; the expiry loop
            // clears it when the tag year runs out. See `Player.franchiseTagSeason`.
            player.franchiseTagSeason = bindingSeason
            player.restructureReliefK = 0
            player.restructureProrationK = 0
            player.restructureCarryYears = 0
            settled += 1
        }

        return settled + deferredSettled
    }

    /// **Writes a settled deferred extension onto the `Contract` row**, so the
    /// deal that just started is the deal every realistic-mode surface reads.
    ///
    /// Without this the row still describes the contract the extension replaced,
    /// and `Contract.capHit` is the only number the cap screen, `applyRelease`'s
    /// dead-money split and the NEXT negotiation's `previousCharge` have: the
    /// club shows — and nets — the expired rate while the true-up charges the
    /// new one, so `currentCapUsage` is overstated by the difference and the
    /// screen's own ledger-variance warning fires against a figure that is right.
    ///
    /// The schedule written is FLAT, and deliberately: `annualSalary` is the flat
    /// `annualCapHit` and the rollover's true-up sums exactly that, so a flat row
    /// makes `capHit == annualSalary` in every year of the deal — the two ledgers
    /// cannot disagree. The bonus is recovered the way the offer built it
    /// (`annualCapHit = annualSalary + signingBonus / years`), which keeps a
    /// release's acceleration honest, and the guarantee and no-trade clause come
    /// off the row rather than being invented here.
    private static func settleDeferredContract(
        row: CommittedCapLedger.Reservation,
        teamID: UUID,
        contract: Contract?
    ) {
        // Simple and sandbox mode carry no `Contract` row at all, and neither
        // does a save whose player was never given one; `annualSalary` is the
        // whole of their books and it is already written.
        guard let contract else { return }

        let years = max(1, row.years)
        let base = max(0, row.offeredSalary)
        let prorated = max(0, row.annualCapHit - base)
        let bonus = prorated * years
        let schedule = Array(repeating: base, count: years)
        let guaranteed = row.guaranteedMoney ?? bonus
        let noTrade = row.noTradeClause ?? false

        contract.teamID = teamID
        contract.totalYears = years
        contract.currentYear = 0
        contract.baseSalary = schedule
        contract.signingBonus = bonus
        contract.guaranteedMoney = guaranteed
        contract.noTradeClause = noTrade
        contract.franchiseTagged = false
    }

    /// The fifth-year price for one man, in thousands.
    ///
    /// `.sandbox` deliberately still gets a real number. That mode switches the
    /// CAP off, not the contract — `franchiseTagValue` answers 0 there because a
    /// tag costs a sandbox club nothing, and writing a 0 (or a
    /// veteran-minimum) fifth year would make the option a free superstar
    /// rather than a switched-off constraint. The price is therefore always read
    /// at the realistic tag, and `.sandbox` drops the AFFORDABILITY test in
    /// ``settleFifthYearOptions`` instead — the same split ``resignAIOwnCore``
    /// uses.
    ///
    /// Floored at the veteran minimum so a position nobody in the league is paid
    /// for yet cannot produce a sub-minimum contract.
    static func fifthYearOptionPrice(
        player: Player,
        salaryTable: [Position: [Int]],
        salaryCap: Int
    ) -> Int {
        let tag = ContractEngine.franchiseTagValue(
            position: player.position,
            topSalaries: salaryTable[player.position] ?? [],
            capMode: .realistic,
            salaryCap: salaryCap
        )
        return max(
            Int(fifthYearOptionTagShare * Double(tag)),
            ContractEngine.veteranMinimum(cap: salaryCap)
        )
    }

    /// **The one place a fifth year is picked up**, so the user's button and the
    /// AI's rollover pass write the identical mutation.
    ///
    /// Flat-salary model, deliberately: the game carries one `annualSalary` per
    /// contract, not a per-year schedule, so a picked-up option raises the whole
    /// remaining deal to the option number rather than only the fifth year. The
    /// club therefore overpays slightly in year four (option money instead of
    /// rookie-slot money) and pays exactly right in year five. That is the
    /// honest approximation available inside a flat-salary contract, it errs
    /// AGAINST the club picking the option up — which is the right direction for
    /// a decision that is supposed to be a real commitment — and it keeps every
    /// cap read in the app (true-up, `availableCap`, the retention budget) a
    /// single multiplication away from the truth.
    ///
    /// `contractYearsRemaining += 1` and NOT `= 3`: read before the decrement it
    /// takes the sheet from 2 to 3, the expiry loop takes it back to 2, and he
    /// plays year four and year five. Written as an increment so the one thing
    /// this function promises — "he owes the club one more season than he did" —
    /// survives any contract shape.
    static func exerciseFifthYearOption(player: Player, team: Team?, price: Int) {
        let previousSalary = player.annualSalary
        player.contractYearsRemaining += 1
        player.annualSalary = price
        player.fifthYearDecided = true
        player.fifthYearExercised = true
        // `executeNewLeagueYear`'s true-up rebuilds usage from rostered salaries
        // a few lines later and would reach the same number, but the user's
        // screen reads `availableCap` the instant the button is pressed — hours
        // of play before that rebuild — so the ledger is kept honest here too.
        team?.currentCapUsage += price - previousSalary
    }

    /// The other answer: nothing changes. He plays out year four on rookie
    /// money and reaches the market a year later, which is what makes the
    /// decline the realistic outcome for most of round 1.
    static func declineFifthYearOption(player: Player) {
        player.fifthYearDecided = true
        player.fifthYearExercised = false
    }

    /// One club's verdict on one option. AI-only — the user's answer comes from
    /// `FinalPushView`.
    ///
    /// Two doors to yes, because a fourth-year rookie is judged on two different
    /// things depending on what he is. `marketAppeal` carries the age discount
    /// and the upside premium, so the 23-year-old at 74 who is still climbing
    /// clears it; `overall` catches the man who is simply good now. Below both
    /// the club declines — and MOST of round 1 is below both, which is the
    /// realism the feature exists for: the mid-to-late first-round pick who did
    /// not hit does not get a fifth year at 80 % of the franchise tag.
    static func shouldExerciseFifthYearOption(player: Player) -> Bool {
        marketAppeal(player) >= fifthYearOptionAppealFloor
            || player.overall >= fifthYearOptionOverallFloor
    }

    /// Settle every outstanding fifth-year option in the league for this league
    /// year. Returns the number of options exercised.
    ///
    /// Runs INSIDE ``executeNewLeagueYear``, ahead of ``resignAIOwnCore`` and
    /// therefore ahead of the expiry loop. Both orderings are load-bearing:
    ///
    /// * before the expiry loop, because the whole window is defined
    ///   pre-decrement (see ``isFifthYearOptionWindow``), and because
    ///   `contractYearsRemaining += 1` here is what the loop's `-= 1` cancels;
    /// * before `resignAIOwnCore`, because that function budgets a club's
    ///   retentions against the payroll that SURVIVES the rollover
    ///   (`contractYearsRemaining > 1`), and a picked-up option is exactly such
    ///   a commitment. Settling first means a club that has just guaranteed
    ///   $18M to its fourth-year corner cannot also promise that money to a
    ///   free agent.
    ///
    /// The USER's club is not decided FOR him — it is only closed out. Anything
    /// still undecided on his roster when the league year turns is a decline,
    /// which is the same self-heal the rest of the offseason uses for a screen
    /// the user walked away from: the deadline passed, so the answer is no.
    @discardableResult
    static func settleFifthYearOptions(
        allPlayers: [Player],
        allTeams: [Team],
        userTeamID: UUID?,
        capMode: CapMode = .simple,
        career: Career? = nil
    ) -> Int {
        // Closure and not a bare `filter(isFifthYearOptionWindow)`: a method
        // REFERENCE does not inherit the caller's actor isolation, so the
        // point-free form warns (and is an error under Swift 6).
        let candidates = allPlayers.filter { isFifthYearOptionWindow($0) }
        guard !candidates.isEmpty else { return 0 }

        var teamsByID: [UUID: Team] = [:]
        for team in allTeams { teamsByID[team.id] = team }
        let salaryTable = positionSalaryTable(allPlayers: allPlayers)

        var exercised = 0
        var news: [NewsItem] = []

        for player in candidates {
            guard let teamID = player.teamID, let team = teamsByID[teamID] else { continue }
            let price = fifthYearOptionPrice(
                player: player,
                salaryTable: salaryTable,
                salaryCap: team.salaryCap
            )
            // What the option ADDS to the books. The man is already on the
            // roster at rookie money, so the club is only being asked for the
            // difference — charging it the whole option number would price a
            // decision it has partly already paid for.
            let capDelta = price - player.annualSalary

            // The user's club: never decided for, only closed out.
            if teamID == userTeamID {
                declineFifthYearOption(player: player)
                news.append(fifthYearNews(
                    player: player, team: team, price: price,
                    exercised: false, lapsed: true, career: career
                ))
                continue
            }

            // `availableCap` and not the reserve-aware budget `resignAIOwnCore`
            // builds, for two reasons. It is the brief's own test ("room after
            // the option price stays at or above zero"), and it is the number
            // `FinalPushView` prints in its Cap Space pill — so the AI is judged
            // by exactly the yardstick the user is shown. Both read the ledger
            // BEFORE this function's true-up, i.e. still carrying the league
            // year's dead money, which makes every club look a little poorer
            // than it will be an hour later. That pessimism is deliberate and
            // symmetric: it pushes marginal options toward decline, which is the
            // realistic answer for most of round 1 anyway.
            let affordable = capMode == .sandbox || team.availableCap >= capDelta
            guard shouldExerciseFifthYearOption(player: player), affordable else {
                declineFifthYearOption(player: player)
                if let item = notableFifthYearNews(
                    player: player, team: team, price: price,
                    exercised: false, career: career
                ) { news.append(item) }
                continue
            }

            exerciseFifthYearOption(player: player, team: team, price: price)
            exercised += 1
            ChurnDiag.record(ChurnDiag.option5, player)
            if let item = notableFifthYearNews(
                player: player, team: team, price: price,
                exercised: true, career: career
            ) { news.append(item) }
        }

        if let career, !news.isEmpty {
            career.newsLog = news + career.newsLog
        }
        return exercised
    }

    /// Overall at which an option decision is league news rather than a
    /// transaction line. The user's own club is always news regardless — it is
    /// his roster.
    private static let fifthYearNewsOverall = 80

    private static func notableFifthYearNews(
        player: Player,
        team: Team,
        price: Int,
        exercised: Bool,
        career: Career?
    ) -> NewsItem? {
        guard player.overall >= fifthYearNewsOverall else { return nil }
        return fifthYearNews(
            player: player, team: team, price: price,
            exercised: exercised, lapsed: false, career: career
        )
    }

    private static func fifthYearNews(
        player: Player,
        team: Team,
        price: Int,
        exercised: Bool,
        lapsed: Bool,
        career: Career?
    ) -> NewsItem {
        let money = "$\(String(format: "%.1f", Double(price) / 1_000.0))M"
        let headline: String
        let body: String
        if exercised {
            headline = "\(team.abbreviation) pick up \(player.fullName)'s fifth-year option"
            body = "The \(team.fullName) have exercised the fifth-year option on \(player.position.rawValue) \(player.fullName), guaranteeing him \(money) for a fifth season. The \(player.overall)-overall former first-round pick is now under contract through the end of his option year."
        } else if lapsed {
            headline = "\(team.abbreviation) let \(player.fullName)'s option deadline pass"
            body = "The \(team.fullName) declined the fifth-year option on \(player.position.rawValue) \(player.fullName), which would have cost \(money). He plays out the final year of his rookie deal and can reach free agency next spring."
        } else {
            headline = "\(team.abbreviation) decline \(player.fullName)'s fifth-year option"
            body = "The \(team.fullName) will not pick up the \(money) fifth-year option on \(player.position.rawValue) \(player.fullName). The former first-round pick enters the last year of his rookie contract and is a year from the open market."
        }
        return NewsItem(
            headline: headline,
            body: body,
            category: .contract,
            week: career?.currentWeek ?? 0,
            season: career?.currentSeason ?? 0,
            relatedTeamID: team.id,
            relatedPlayerID: player.id,
            sentiment: exercised ? .positive : .negative
        )
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
    /// - Parameter season: seeds the veteran fog, re-rolled per league year
    ///   (`AIDraftPerception.veteranRead`).
    static func simulateAIFreeAgency(
        freeAgents: [FreeAgent],
        teams: [Team],
        modelContext: ModelContext,
        capMode: CapMode = .simple,
        allPlayers: [Player]? = nil,
        season: Int
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

        // Task #89 — each club's own board of genuine holes, computed once for
        // the whole market. Blending it with the depth ladder below is what stops
        // the market handing the ninth receiver to the club that already has
        // eight of them purely because that club is rich.
        //
        // `teamNeedDeficits` and NOT `topTeamNeeds`: the latter ranks by
        // positional value as well as deficit, and on a full roster the deficit
        // term is 1.0 nearly everywhere, so it returns the same five positions
        // — {QB, DE, CB, WR, LT} — for all 32 clubs. Multiplying `topNeedBonus`
        // onto that is not a need model at all, it is a flat league-wide premium
        // on five positions, applied to every club equally and therefore
        // cancelling out of the very comparison it was written to inform.
        //
        // Task #92c reads the FULL deficit list off the same call and keeps the
        // top five for the bonus, so the two questions ("does this club have any
        // deficit here at all" and "is this one of its five biggest") come from
        // one ranking rather than two.
        var topNeedsByTeam: [UUID: Set<Position>] = [:]
        var deficitPositionsByTeam: [UUID: Set<Position>] = [:]
        // Task #91 — each club's competitive stance, computed ONCE for the whole
        // market run. It derives from a 24-man core sort over the roster, so
        // asking for it per free agent would be ~500 roster sorts × 32 clubs.
        var stanceByTeam: [UUID: TradeValueEngine.TeamStance] = [:]
        if let rosterPlayers = allPlayers, !rosterPlayers.isEmpty {
            var rosterByTeam: [UUID: [Player]] = [:]
            for player in rosterPlayers {
                guard let teamID = player.teamID, !player.isRetired else { continue }
                rosterByTeam[teamID, default: []].append(player)
            }
            let coreReference = TradeValueEngine.leagueCoreReference(allPlayers: rosterPlayers)
            for team in teams {
                let roster = rosterByTeam[team.id] ?? []
                let deficits = DraftEngine.teamNeedDeficits(
                    roster: roster,
                    limit: Position.allCases.count
                )
                deficitPositionsByTeam[team.id] = Set(deficits)
                topNeedsByTeam[team.id] = Set(deficits.prefix(5))
                stanceByTeam[team.id] = TradeValueEngine.stance(
                    for: team,
                    roster: roster,
                    coreReference: coreReference
                )
            }
        }

        // F-23 — one veteran lens per club, hoisted for the same reason as
        // everything else in this block.
        let veteranLensByTeam: [UUID: AIDraftPerception.Lens] = Dictionary(
            uniqueKeysWithValues: teams.map { ($0.id, AIDraftPerception.veteranLens(forTeam: $0.id)) }
        )

        // Task #91 — the GM's own settlement bias. `forTeam` is a UUID-byte
        // draw, but it is a draw per free agent otherwise, so it is cached with
        // everything else the run needs per club.
        var settlementLeanByTeam: [UUID: Double] = [:]
        for team in teams {
            settlementLeanByTeam[team.id] = settlementLean(
                TradeValueEngine.GMPersona.forTeam(id: team.id).archetype
            )
        }

        // Task #92c — the market in POSITION-GROUP order, with a cursor per
        // group, so "what would it cost me to fill my hole at LT" is an O(1)
        // question instead of a scan of the pool per club per agent.
        //
        // Sorted by PRICE, not by market appeal. The reserve answers "what must
        // I keep back to man this slot", and the honest answer is the cheapest
        // starter on the board, not the most expensive one: pricing it at the
        // group's best man reserved a franchise-receiver number to fill a TE2
        // hole and took the club out of the rest of the market for it. Two lists
        // per group — starter-quality first, everybody as the fallback — each
        // with a forward-only cursor, so the cheapest UNSIGNED man is still an
        // O(1) read.
        var groupStarterPool: [Position: [FreeAgent]] = [:]
        var groupAnyPool: [Position: [FreeAgent]] = [:]
        for agent in sortedAgents {
            let key = positionGroupKey(for: agent.player.position)
            groupAnyPool[key, default: []].append(agent)
            if agent.player.overall >= starterQualityOVR {
                groupStarterPool[key, default: []].append(agent)
            }
        }
        for key in groupAnyPool.keys {
            groupAnyPool[key]?.sort { $0.askingPrice < $1.askingPrice }
            groupStarterPool[key]?.sort { $0.askingPrice < $1.askingPrice }
        }
        var groupStarterCursor: [Position: Int] = [:]
        var groupAnyCursor: [Position: Int] = [:]
        func cheapestUnsigned(_ pool: [Position: [FreeAgent]], _ cursor: inout [Position: Int], _ key: Position) -> Int {
            guard let list = pool[key] else { return 0 }
            var index = cursor[key] ?? 0
            while index < list.count, list[index].player.teamID != nil { index += 1 }
            cursor[key] = index
            return index < list.count ? list[index].askingPrice : 0
        }
        /// What manning `position`'s group costs at replacement level.
        func replacementAsk(inGroupOf position: Position) -> Int {
            let key = positionGroupKey(for: position)
            let starter = cheapestUnsigned(groupStarterPool, &groupStarterCursor, key)
            if starter > 0 { return starter }
            // Nobody left in the group can start. The slot is still unmanned, so
            // the club keeps back what the cheapest BODY costs rather than
            // nothing at all — and 0 (empty group) still releases the reserve
            // entirely, which is what keeps a QB-less club able to buy a QB.
            return cheapestUnsigned(groupAnyPool, &groupAnyCursor, key)
        }

        // Task #92c — one reserve per club, memoised because a club's holes only
        // change when it signs somebody. Invalidated on that signing below.
        var criticalHoleByTeam: [UUID: Position?] = [:]
        func criticalHole(_ teamID: UUID) -> Position? {
            if let cached = criticalHoleByTeam[teamID] { return cached }
            let hole = needIndex?.topCriticalHole(teamID: teamID)
            criticalHoleByTeam[teamID] = hole
            return hole
        }

        /// One free agent's turn on the market.
        ///
        /// - Parameter holdHoleReserves: task #92c. While true, a club that is
        ///   already stocked at this man's position must still be able to afford
        ///   its own unmanned starter slot after signing him. Released on the
        ///   mop-up wave so the money can never sit dead.
        func attemptSigning(_ agent: FreeAgent, holdHoleReserves: Bool, floorWave: Bool = false) {
            // Skip players who were already signed this cycle
            guard agent.player.teamID == nil else { return }
            let agentPosition = agent.player.position
            let agentGroup = positionGroupKey(for: agentPosition)

            // Task #92c — what this club must keep back before it may spend on
            // THIS man. Zero unless all four hold: the reserve is armed, the club
            // has an unmanned starter slot somewhere, that slot is not the one he
            // would fill, and it has no deficit at his position either (a club
            // that is genuinely short of receivers is allowed to buy a receiver).
            func holeReserve(for team: Team) -> Int {
                guard holdHoleReserves else { return 0 }
                guard let hole = criticalHole(team.id) else { return 0 }
                guard positionGroupKey(for: hole) != agentGroup else { return 0 }
                guard deficitPositionsByTeam[team.id]?.contains(agentPosition) != true else { return 0 }
                return replacementAsk(inGroupOf: hole)
            }

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
                        // D2(b): a club under the CBA's 89 % cash floor spends its
                        // reserve. The floor is the mechanism that produces a
                        // veteran market at all — a club that is legally required
                        // to spend will sign a man it does not need, which is
                        // exactly what real clubs do every March and what this
                        // league has never done. `amountBelowFloor` has modelled
                        // the rule since it was written and had ZERO callers.
                        let underFloor = floorWave
                            && CapManagementEngine.amountBelowFloor(team: team, capMode: capMode) > 0
                        let reserve = underFloor
                            ? 0
                            : Int(Double(team.salaryCap) * capReserve(forTeam: team.id))
                        let hole = holeReserve(for: team)
                        guard team.availableCap - reserve - hole >= agent.askingPrice else { return false }
                        guard let needIndex else { return true }
                        return needIndex.rosterSize(teamID: team.id) < faRosterCeiling
                    }
                    .sorted { $0.availableCap > $1.availableCap }
            case .sandbox:
                eligibleTeams = teams.shuffled()
            }

            // R23: need-first ordering when roster data is available.
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
                // Task #92a — a club with NO need at the position is not a buyer.
                // `needy + rest` meant the shortlist was topped up from
                // `rest` — which is ordered by CAP SPACE — whenever fewer than
                // `marketInterest` clubs had a hole, i.e. every time a position is
                // well stocked league-wide (the normal case at WR, CB and DE). The
                // richest club in the league therefore bought the ninth receiver
                // for a room that already had eight. `rest` survives only as the
                // fallback that keeps the man employable at all, which is what
                // preserves the contract COUNT task #53 calibrated.
                eligibleTeams = needy.isEmpty ? rest : needy
            }

            // Pick from the top interested teams (capped by marketInterest)
            let candidateCount = min(agent.marketInterest, eligibleTeams.count)
            guard candidateCount > 0 else { return }

            let candidates = Array(eligibleTeams.prefix(candidateCount))

            // Pick the winner out of the shortlist, weighted by how good the
            // building is at developing players (§5.1) AND by how badly it needs
            // the position (task #89 — see `needWeight`). Shortlist membership is
            // untouched, so the market still writes exactly the same number of
            // contracts; this only decides which of those clubs wins each one.
            guard let winningTeam = weightedPick(
                candidates,
                weight: { team in
                    var weight = appealByTeam[team.id] ?? 1.0
                    if let needIndex {
                        weight *= needWeight(needIndex.need(teamID: team.id, position: agentPosition))
                    }
                    if topNeedsByTeam[team.id]?.contains(agentPosition) == true {
                        weight *= topNeedBonus
                    }
                    // Task #91 — the club's competitive cycle. A contender leans
                    // toward the win-now veteran and a rebuilder toward the man
                    // who will still be there when it is good again; the trade
                    // market has priced exactly this since Wave 2 and free agency
                    // did not consult it at all. Bounded to a nudge — need still
                    // outranks taste (see `marketPersonalityLeanCap`).
                    if let stance = stanceByTeam[team.id] {
                        weight *= boundedStanceLean(
                            stance.incomingAgeMultiplier(age: agent.player.age)
                        )
                    }
                    // F-23 / D3 Option A — THE VETERAN FOG, on the bulk market.
                    //
                    // The interactive path expresses a club's opinion as money
                    // because there the BID is the decision. Here the decision is
                    // a weighted pick — who ends up wanting him most — so the fog
                    // lands on the wanting. Same model, same seed, attached to
                    // whatever each path actually decides.
                    //
                    // This is what produces the two stories free agency has never
                    // been able to tell: the club that talks itself into a man the
                    // rest of the league has right, and the good player who slides
                    // because the room that needed him read him low.
                    let perceived = AIDraftPerception.veteranRead(
                        teamID: team.id,
                        playerID: agent.player.id,
                        season: season,
                        trueOverall: agent.player.overall,
                        truePotential: agent.player.truePotential,
                        lens: veteranLensByTeam[team.id]
                    )
                    let readError = perceived.overall - Double(agent.player.overall)
                    weight *= max(
                        1.0 - perceptionWantSwingCap,
                        min(1.0 + perceptionWantSwingCap, 1.0 + readError * perceptionWantPerOVR)
                    )
                    return weight
                }
            ) else { return }

            // The AI GM negotiates against the SAME demand model the user does:
            // he lands somewhere between the agent's floor and his opening ask,
            // never below the floor. The old `ask × random(0.85…1.0)` had no
            // floor under it at all, which is how an AI club could buy a man for
            // less than the user's agent would ever have taken.
            let minimum = max(Int(0.0028 * Double(winningTeam.salaryCap)), 750)
            let floor = min(agent.floorPrice, agent.askingPrice)
            // Task #91 — WHERE in that band he lands is his own trait, not a
            // league constant. See `settlementLean` for the bound.
            let lean = settlementLeanByTeam[winningTeam.id] ?? 1.0
            let draw = pow(Double.random(in: 0...1), 1.0 / lean)
            var settlement = Double(floor) + Double(agent.askingPrice - floor) * draw
            // D2(b) — the FLOOR PREMIUM: a club under the CBA's 89 % cash floor
            // pays ABOVE the ask.
            //
            // The floor was first modelled as an extra signing wave, and it did
            // nothing measurable: payroll went 71.6 → 64.3 → 73.9 → 81.7 % with
            // the wave against 71.8 → 65.0 → 76.5 → 83.9 % without it. The reason
            // is structural and worth writing down — **the roster ceiling binds
            // before the money does.** A club with cap room and no open seats
            // cannot spend its way to the floor by signing MORE men, and that is
            // not how real clubs do it either: the floor is a CASH requirement,
            // so it is met by paying more per player, by extending your own, and
            // by absorbing salary in trades. Volume was the wrong lever.
            //
            // Premium scales with the shortfall, capped at +25 %: a club a
            // rounding error under the line nudges, a club 20 % under it bids
            // like it means it. This is also the honest half of the "loser tax" —
            // a bad club paying over the odds is exactly what the free-agency
            // audit found the game doing BACKWARDS.
            let shortfall = CapManagementEngine.amountBelowFloor(team: winningTeam, capMode: capMode)
            if shortfall > 0, winningTeam.salaryCap > 0 {
                let gap = Double(shortfall) / Double(winningTeam.salaryCap)   // 0…~0.25 in practice
                settlement *= 1.0 + min(0.25, gap * 1.5)
            }
            let agreedSalary = max(Int(settlement), minimum)
            // Task #89: the club gets a say in the TERM as well as the price.
            // `desiredYears` is the player's wish; `contractYearsCeiling` is what
            // a front office will actually commit to at his age.
            let agreedYears = max(
                1,
                min(agent.desiredYears, contractYearsCeiling(age: agent.player.age))
            )

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
            // Task #92c: his club's hole board just changed.
            criticalHoleByTeam.removeValue(forKey: winningTeam.id)
        }

        for agent in sortedAgents {
            attemptSigning(agent, holdHoleReserves: true)
        }

        // Task #92c — the mop-up wave, with every hole reserve released.
        //
        // This is what stops the reserve from turning into dead money: a club
        // that held back a left tackle's wage all market and never found one is
        // free to spend it here. It cannot inflate the number of contracts the
        // market writes, because the only men it can reach are the ones the wave
        // above left unsigned — and the ONLY reason a wave-1 agent goes unsigned
        // with clubs still holding room is the reserve itself. Cap and roster
        // exhaustion are unchanged by this pass (both only ever tightened above).
        for agent in sortedAgents where agent.player.teamID == nil {
            attemptSigning(agent, holdHoleReserves: false)
        }

        // D2(b) — the FLOOR wave, last, on whoever is still unsigned.
        //
        // The two waves above are need-driven: a club bids because it wants the
        // man. This one is law-driven — the CBA requires 89 % of the cap to be
        // spent in cash, and a club below that line has to write a cheque whether
        // or not it has a hole. Measured before this existed: league payroll
        // 64.5-79.8 % of the cap and 31-32 of 32 clubs comfortably compliant
        // every season, which is why the veteran market was permanently thin and
        // why nothing ever fell to the user in March.
        //
        // It cannot inflate the market's contract count beyond the men available:
        // like the mop-up it only reaches agents both earlier waves left unsigned.
        // What it changes is WHO can reach them — only a club actually under the
        // floor gets its reserve waived, so a healthy club is unaffected and the
        // reserve keeps meaning what it means everywhere else.
        for agent in sortedAgents where agent.player.teamID == nil {
            attemptSigning(agent, holdHoleReserves: false, floorWave: true)
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

        // Task #92b — same starter-slot rule as `RosterNeedIndex.need`. Kept in
        // lockstep on purpose: `TamperingRumorEngine` prices its leaks off this
        // function, and a rumor mill that disagrees with the market about who
        // has a hole is a rumor mill that lies.
        if isUnmannedStarterSlot(position: position, bestOVR: bestOVR) {
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
        // Four rooms of one, not one room of four: a club short a snapper
        // cannot cover the hole with its punter, so each has to be its own
        // deficit or the market never signs one.
        case .LS:                    return ([.LS], 1)
        case .H:                     return ([.H], 1)
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
    /// - Parameter season: the league year, which seeds the veteran fog. It is
    ///   re-rolled annually on purpose — a club that misjudged a man in 2028 has
    ///   two more seasons of film on him by 2030 and is allowed to change its
    ///   mind. See `AIDraftPerception.veteranRead`.
    static func generateAIOffers(
        freeAgents: [FreeAgent],
        round: Int,
        allTeams: [Team],
        allPlayers: [Player]? = nil,
        playerTeamID: UUID?,
        capMode: CapMode = .simple,
        season: Int
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

        // F-23: one lens per club, hoisted out of the agent x team loop. The
        // lens is a `GMPersona` lookup and a switch; the READ is the per-pair
        // work and stays inside.
        let veteranLensByTeam: [UUID: AIDraftPerception.Lens] = Dictionary(
            uniqueKeysWithValues: aiTeams.map { ($0.id, AIDraftPerception.veteranLens(forTeam: $0.id)) }
        )

        // Task #89 — the same draft board the bulk market reads.
        var topNeedsByTeam: [UUID: Set<Position>] = [:]
        // Task #92c — every position the club is genuinely short at, so the hole
        // reserve below can tell "we are stocked here" from "this is one of our
        // five biggest holes".
        var deficitPositionsByTeam: [UUID: Set<Position>] = [:]
        // Task #91 — the club's competitive cycle, cached per team for the whole
        // round exactly as the bulk market caches it for the whole run.
        var stanceByTeam: [UUID: TradeValueEngine.TeamStance] = [:]
        if !rosterPlayers.isEmpty {
            var rosterByTeam: [UUID: [Player]] = [:]
            for player in rosterPlayers {
                guard let teamID = player.teamID, !player.isRetired else { continue }
                rosterByTeam[teamID, default: []].append(player)
            }
            let coreReference = TradeValueEngine.leagueCoreReference(allPlayers: rosterPlayers)
            for team in aiTeams {
                let roster = rosterByTeam[team.id] ?? []
                let deficits = DraftEngine.teamNeedDeficits(
                    roster: roster,
                    limit: Position.allCases.count
                )
                deficitPositionsByTeam[team.id] = Set(deficits)
                topNeedsByTeam[team.id] = Set(deficits.prefix(5))
                stanceByTeam[team.id] = TradeValueEngine.stance(
                    for: team,
                    roster: roster,
                    coreReference: coreReference
                )
            }
        }

        // Task #92c — one reserve per club: its unmanned starter slot, priced at
        // REPLACEMENT level, i.e. the cheapest man on the board who could
        // actually start there.
        //
        // Not the group's best man. Pricing it at the top free agent in the
        // group reserved a franchise number to fill a TE2 or a kicker slot and
        // took the club out of the rest of the market for it — and after the
        // rollover, rosters sit near 40 against ideal counts summing to 39, so
        // `count == 0` holes are common and a large share of the league was
        // affected at once. The cheapest starter is what the club actually has
        // to keep back; anything more is not a plan, it is a freeze.
        //
        // Computed once per round rather than per bid, and RELEASED from round 5
        // on. Round 5's OVR floor is 65 and round 6's is 60 — both below
        // `starterQualityOVR` — so from there the board cannot fill a starter
        // slot at all and holding money for one is holding it for nothing. (It
        // used to release only in round 6, which meant clubs sat out five of the
        // six rounds the user actually watches.)
        let holdHoleReserves = round < 5
        var holeReserveByTeam: [UUID: (position: Position, amount: Int)] = [:]
        if holdHoleReserves, let needIndex {
            for team in aiTeams {
                guard let hole = needIndex.topCriticalHole(teamID: team.id) else { continue }
                let group = Set(positionGroupInfo(for: hole).positions)
                let unsigned = freeAgents.filter {
                    $0.player.teamID == nil && group.contains($0.player.position)
                }
                let price = unsigned
                    .filter { $0.player.overall >= starterQualityOVR }
                    .min(by: { $0.askingPrice < $1.askingPrice })?.askingPrice
                    ?? unsigned.min(by: { $0.askingPrice < $1.askingPrice })?.askingPrice
                guard let price else { continue }
                holeReserveByTeam[team.id] = (position: hole, amount: price)
            }
        }
        /// What `team` must keep back before it may bid on a `position` it is
        /// already set at. Same four conditions as the bulk market's.
        func holeReserve(team: Team, position: Position) -> Int {
            guard let entry = holeReserveByTeam[team.id] else { return 0 }
            guard positionGroupKey(for: entry.position) != positionGroupKey(for: position) else { return 0 }
            guard deficitPositionsByTeam[team.id]?.contains(position) != true else { return 0 }
            return entry.amount
        }

        for fa in freeAgents {
            guard fa.player.teamID == nil else { continue }
            // Task #89 — WHEN a free agent enters the market is age-aware here
            // too. This gate used to read raw `overall`, so the interactive
            // path (the one a real career actually plays) still ran the "cuts on
            // youth, signs on age" ratchet task #53 removed from the bulk market:
            // a 33-year-old 84-OVR end was bid on a full round EARLIER than a
            // 26-year-old 79 with an 85 ceiling, and `estimateMarketValue` then
            // sold him ~20 % cheaper on top. `marketAppeal` grades them 70.0 and
            // 81.7, which is the order a front office would use.
            //
            // The FINAL round deliberately keeps the raw-`overall` floor, so
            // nobody who used to receive an AI bid across the six rounds has
            // stopped receiving one. The set is not identical, though, and the
            // difference is a feature rather than a leak: `marketAppeal` credits
            // 0.45 of untapped ceiling for a player at four years' service or
            // fewer, so a 22-year-old at 58 OVR with a 74 ceiling grades 65.2 and
            // now draws a round-5 bid he never used to draw at all. Clubs sign
            // young men on upside. The gate GROWS the bid-receiving set at the
            // young end and moves everyone else's entry round; it never shrinks
            // it, because round 6 still admits anyone at 60.
            let clearsTier = round >= 6
                ? fa.player.overall >= targetMinOVR
                : marketAppeal(fa.player) >= Double(targetMinOVR)
            guard clearsTier else { continue }

            var bids: [AIBid] = []

            for team in aiTeams {
                // Skip cap gating entirely in sandbox mode.
                //
                // Task #27: the same reserve the bulk market keeps. This is the
                // path a real career's free-agent weeks run through, so if only
                // `simulateAIFreeAgency` budgeted, the user's league would still
                // spend itself broke — the two are one market and have to price
                // against one bank balance.
                // Task #92c: plus whatever this club owes its own unmanned
                // starter slot, so a rich team with no quarterback stops
                // outbidding everybody for a fourth receiver first.
                let hole = holeReserve(team: team, position: fa.player.position)
                if capMode != .sandbox {
                    let reserve = Int(Double(team.salaryCap) * capReserve(forTeam: team.id))
                    guard team.availableCap - reserve - hole >= fa.askingPrice else { continue }
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

                // Need-based multiplier. Task #89 adds a bounded nudge when the
                // position is also one of the club's five biggest holes on
                // `DraftEngine.topTeamNeeds` — smaller than the width of the
                // random band below, so it can tilt a close bid and never
                // manufacture one.
                let needRange = needMultiplier(for: need)
                var needFactor = Double.random(in: needRange)
                if topNeedsByTeam[team.id]?.contains(fa.player.position) == true {
                    needFactor *= 1.10
                }
                // Task #91 — the interactive half of the stance lean. This path
                // has no shortlist to weight, so the club's appetite shows up
                // where its appetite is actually expressed: in the money. A
                // contender bids up the 29-year-old it wants for January; a
                // rebuilder does not. Bounded by `marketPersonalityLeanCap`,
                // which is narrower than the `needMultiplier` band it multiplies,
                // so it tilts a bid and never manufactures one.
                if let stance = stanceByTeam[team.id] {
                    needFactor *= boundedStanceLean(
                        stance.incomingAgeMultiplier(age: fa.player.age)
                    )
                }

                // F-23 / D3 Option A — THE VETERAN FOG.
                //
                // Until this line every AI club read every free agent's true
                // `overall`. All 31 rooms valued all ~500 veterans identically
                // and correctly: nobody ever signed a bust, nobody let a good
                // player walk because they misjudged him, nobody overpaid for a
                // name. The draft has had a measured fog since
                // `AIDraftPerception`; free agency had none at all.
                //
                // The club now prices off what IT thinks the man is, and the
                // error is deterministic per `(club, player, league year)`,
                // persona-shaped and fat-tailed — so a room is wrong about the
                // same veteran all winter, an old-school room is wrong more
                // often than an analytics one, and roughly one read in
                // twenty-five is wrong enough to become a story.
                //
                // It is expressed as MONEY rather than as a re-rating, because
                // that is where a front office's opinion actually surfaces and
                // because it leaves the market's queue (`marketAppeal`, the
                // league-wide consensus order) alone. `perceptionPricePerOVR` is
                // deliberately small: ±2 OVR of misread moves a bid ~6 %, enough
                // to lose or win a contested signing without turning the market
                // into noise.
                let perceived = AIDraftPerception.veteranRead(
                    teamID: team.id,
                    playerID: fa.player.id,
                    season: season,
                    trueOverall: fa.player.overall,
                    truePotential: fa.player.truePotential,
                    lens: veteranLensByTeam[team.id]
                )
                let readError = perceived.overall - Double(fa.player.overall)
                let perceptionFactor = max(
                    1.0 - perceptionPriceSwingCap,
                    min(1.0 + perceptionPriceSwingCap, 1.0 + readError * perceptionPricePerOVR)
                )

                // Combine need with round aggression
                let salaryMultiplier = needFactor
                    * perceptionFactor
                    * Double.random(in: (aggression * 0.85)...(aggression * 1.05 + 0.05))

                // Cap-aware: don't bid more than 30% of remaining cap on one player.
                // Sandbox skips this clamp so bids reflect raw demand only.
                let minimum = max(Int(0.0028 * Double(team.salaryCap)), 750)
                let rawOffer = Int(Double(fa.askingPrice) * salaryMultiplier)
                let offeredSalary: Int
                if capMode == .sandbox {
                    offeredSalary = max(rawOffer, minimum)
                } else {
                    // 30 % of SPENDABLE room, not of nominal room — the reserve
                    // is not the club's to bid with (task #27), and neither is
                    // the hole reserve (task #92c).
                    let reserve = Int(Double(team.salaryCap) * capReserve(forTeam: team.id))
                    let spendable = max(0, team.availableCap - reserve - hole)
                    let maxBid = Int(Double(spendable) * 0.30)
                    offeredSalary = max(min(rawOffer, maxBid), minimum)
                }

                bids.append(AIBid(
                    teamID: team.id,
                    teamAbbr: team.abbreviation,
                    salary: offeredSalary,
                    // Task #89: the club's own term ceiling, same as the bulk
                    // market's `agreedYears`.
                    years: max(1, min(fa.desiredYears, contractYearsCeiling(age: fa.player.age))),
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

    /// How many clubs on one man count as a war on their own. See
    /// ``processBiddingWars`` for why this is 3 and not 4.
    static let biddingWarMinBidders = 3

    /// How close the second-best offer must be to the best for two clubs to
    /// count as a war without a third. 0.90 = within 10 %.
    static let biddingWarCloseness = 0.90

    struct BiddingWarInfo {
        let playerID: UUID
        let playerName: String
        let position: String
        let bidderCount: Int
        let escalatedPrice: Int   // Price after escalation
        let droppedOutTeams: [String]  // Teams that couldn't keep up
    }

    /// Detect and escalate bidding wars, and report only wars that actually happened.
    ///
    /// ## F-32: the gate was arithmetically unreachable
    ///
    /// The trigger was `bids.count >= 4` while the bid cap upstream is
    /// `maxBidders = Int(aggression x (overall - 60) / 40 x 6)`. Solving the two
    /// against each other gives the minimum OVR a free agent needed before a
    /// fourth club was even ALLOWED to bid on him:
    ///
    /// | round | aggression | min OVR for 4 bidders |
    /// |-------|-----------|-----------------------|
    /// | 1     | 1.00      | 87                    |
    /// | 2     | 0.85      | 92                    |
    /// | 3     | 0.70      | 99                    |
    /// | 4     | 0.50      | 114                   |
    /// | 5     | 0.35      | 137                   |
    /// | 6     | 0.20      | 194                   |
    ///
    /// Rounds 4-6 are impossible; round 3 needs a 99. Against a league whose 90+
    /// band is 1.7-3.1 %, and whose star door keeps the most appealing men off
    /// the open market entirely, the mechanic fired on a handful of players a
    /// decade. It read as "bidding wars are rare"; it was "bidding wars cannot
    /// occur".
    ///
    /// The gate is now `>= 3` bidders **or** the top two offers within 10 % of
    /// each other. The second clause is the one that matters: two clubs a
    /// percent apart IS a bidding war, and it is reachable in every round,
    /// which is what decouples the trigger from the bid cap instead of just
    /// moving it down by one.
    ///
    /// ## F-32: and the receipt described a price nobody paid
    ///
    /// The drop-out test asked `team.availableCap >= escalatedPrice` — the only
    /// cap test in this file that did not subtract the reserve — while the
    /// signing door (`signFreeAgentAI`) refuses on `availableCap - reserve >=
    /// salary`. A club could therefore "stay in", have its raised bid recorded,
    /// be reported to the user at the escalated price, and then be turned away
    /// at the door. Both tests now ask the same question through
    /// `capReserve(forTeam:)`, so a surviving bid is one the door will honour.
    ///
    /// ## And a third bug, found while fixing those two
    ///
    /// `aiBids[playerID] = survivingBids` ran unconditionally. When every bidder
    /// failed the affordability test the player's entire bid list was replaced
    /// with an empty array — so a war nobody could afford did not merely fizzle,
    /// it **erased the offers that already existed** and left the man unsigned
    /// by anyone. A war with fewer than two survivors is now treated as a war
    /// that did not happen: the original bids stand and nothing is reported.
    ///
    /// In sandbox cap mode every team can afford every escalation.
    static func processBiddingWars(
        aiBids: inout [UUID: [AIBid]],
        freeAgents: [FreeAgent],
        allTeams: [Team],
        capMode: CapMode = .simple
    ) -> [BiddingWarInfo] {
        var wars: [BiddingWarInfo] = []

        for (playerID, bids) in aiBids {
            // Three clubs on one man, OR two clubs effectively tied. See the
            // doc comment: the old `>= 4` could not fire past round 3.
            let salariesDescending = bids.map(\.salary).sorted(by: >)
            let topTwoAreClose = salariesDescending.count >= 2
                && salariesDescending[0] > 0
                && Double(salariesDescending[1]) >= Double(salariesDescending[0]) * biddingWarCloseness
            guard bids.count >= biddingWarMinBidders || topTwoAreClose else { continue }
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
                // The SAME question the signing door asks. Anything else
                // reports a price the door will refuse.
                let reserve = Int(Double(team.salaryCap) * capReserve(forTeam: team.id))
                let spendable = team.availableCap - reserve
                let canAfford = (capMode == .sandbox) ? true : (spendable >= escalatedPrice)
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
                        : min(raisedSalary, spendable)
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

            // A war fewer than two clubs can afford is a war that did not
            // happen. Leave the original bids alone — overwriting them with an
            // empty array is how a man nobody could outbid ended up with no
            // offers at all.
            guard survivingBids.count >= 2 else { continue }
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
    ///
    /// ## This must agree with `scoreBid`, and for a while it did not
    ///
    /// `scoreBid` is what actually SIGNS the man. This is what the negotiation
    /// screen shows him leaning toward. D1 rewrote the first and missed the
    /// second, so the display kept the pre-D1 multipliers the ruling deleted:
    /// a flat `× 1.10` for being the user, `× 1.15` more if he wanted to win,
    /// and `1.25 / 0.9` on loyalty. On equal money a loyalty free agent
    /// therefore READ as `1.25 × 1.10 / 0.9 = 1.53` — "Strong interest" — while
    /// the decision underneath scored him `1.06 / 0.98 = 1.08`, a coin flip.
    /// The player was told he was winning men he then lost, which is worse than
    /// either number being wrong on its own.
    ///
    /// The user-side terms now mirror `scoreBid`. They are still two functions,
    /// which is the remaining fragility: `scoreBid` is a local closure over
    /// `player`, `hostedVisit`, `allPlayers` and the record, so sharing one
    /// scorer is a real refactor rather than an extraction. Until that happens,
    /// **any change to one belongs in the other in the same commit.**
    ///
    /// Note that the only call site passes `teamRecord: nil` and
    /// `mediaMarket: nil` for both sides, so the record and market terms below
    /// are inert there — the leaning compares salary and motivation only. That
    /// is why the loser tax does not appear here: it would need real records on
    /// both sides to mean anything, and giving it them is the follow-up, not
    /// this fix.
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
            // D1 removed the `isPlayerTeam × 1.15` from the DECISION; it is gone
            // from the display for the same reason. A man chasing a ring has no
            // reason to prefer the club with a GM on the phone.
            if let record = teamRecord {
                let winPct = Double(record.wins) / Double(max(record.wins + record.losses, 1))
                score *= (1.0 + winPct * 0.15)
            }
        case .stats:
            // The flat 1.05 is motivation, not favouritism, so it stays; the
            // second `isPlayerTeam × 1.05` was the structural bonus D1 deleted.
            score *= 1.05
        case .loyalty:
            // Priced as `scoreBid` prices it — as a pitch, not as a bond the
            // game cannot check (a free agent has no `previousTeamID`).
            score *= isPlayerTeam ? 1.06 : 0.98
        case .fame:
            score *= 1.1
            if let market = mediaMarket {
                score *= market.freeAgentAttraction
            }
        }

        // THE PITCH, at the size `scoreBid` pays for it. This was `× 1.10`.
        if isPlayerTeam {
            score *= 1.02
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
        hostedVisit: Bool = false,
        /// The user club's `Career.fanSupport` (0…100, neutral 50), or `nil`
        /// when the user's club is not among the bidders.
        ///
        /// Asymmetric on purpose and for a structural reason, not a shortcut:
        /// `fanSupport` is a field on `Career`, i.e. the user's save. The other
        /// 31 clubs have no such number, so there is nothing to compare against
        /// and `nil` prices a bid exactly as it was priced before.
        fanSupport: Int? = nil
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

        // D4-C SEAM (F-59) — losing costs you players. A good free agent will
        // not take the call from a club that loses; the magnitude, the gates
        // and the draw all live in `ContractNegotiationEngine
        // .refusesLosingSuitor`, and this is the whole of the wiring. Deliberately
        // a filter over the assembled bids rather than a term inside `scoreBid`:
        // a refusal is not a price, and the loser tax that IS a price is D1's,
        // in `scoreBid`, where it will not collide with this.
        //
        // The empty-result fallback is load-bearing. `scoreBid`'s consumer force
        // -unwraps `max(by:)`, and a market in which every bidder is a losing
        // club is a market that still has to settle — the man signs somewhere.
        let willingBids = allBids.filter {
            !ContractNegotiationEngine.refusesLosingSuitor(player: player, record: $0.teamRecord)
        }
        if !willingBids.isEmpty { allBids = willingBids }

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

        // Check if player wants to shop around (multiple competitive offers,
        // early rounds).
        //
        // Task #93 F8 follow-up: only when the USER is one of the bidders.
        // "Wants to explore all options" is a mechanic aimed at the human — it
        // keeps his offer alive for another round instead of resolving against
        // him immediately. Applied to an all-AI shortlist it does nothing but
        // freeze the market: the caller that honours the flag (`FAWeeklyView`'s
        // AI-vs-AI pass) would leave every contested elite free agent unsigned
        // through rounds 1-2 — the two days whose entire point is the opening
        // splash — and dump them into round 3 at `aiAggression` 0.7.
        if playerOffer != nil && allBids.count >= 2 && round <= 3 {
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
                // The record term that used to live here is now universal and
                // sits below (`loserTax`) — a man who wants to win is the one it
                // weighs HEAVIEST, not the only one it applies to. The extra
                // `bid.isPlayer × 1.15` that used to ride alongside it is gone:
                // a free agent chasing a ring has no reason to prefer the user's
                // club for being the user's club.
                break

            case .stats:
                // Prefers teams where they'll start.
                //
                // D1: the `bid.isPlayer × 1.05` that used to sit here went with
                // the other structural multipliers, and this one was redundant
                // as well as unearned — a stats-motivated man's preference for a
                // starting job is already priced per-bid and at more than double
                // everyone else's weight by the `roleScore` term below (0.30 vs
                // 0.12), against the club's ACTUAL depth chart rather than
                // against who is holding the phone.
                score *= 1.05

            case .loyalty:
                // D1: 1.25 / 0.85 — a 47 % swing in the user's favour, on a
                // "loyalty" the game cannot actually check, because a free agent
                // has no `teamID` to compare against and there is no
                // `previousTeamID` anywhere in `Player`. What the flag really
                // meant was "the club with a GM on the phone", so it is priced
                // as the pitch it is: a few percent, per the ruling.
                score *= bid.isPlayer ? 1.06 : 0.98

            case .fame:
                // Prefers big-market teams
                if let market = bid.mediaMarket {
                    score *= market.freeAgentAttraction
                }
                score *= 1.1
            }

            // D1 — THE LOSER TAX. Applied to every bid on the table, the user's
            // included, and this is the term that inverts the sign.
            score *= loserTax(record: bid.teamRecord, motivation: player.personality.motivation)

            // D1 — THE PITCH, at what a pitch is worth.
            //
            // These two lines were `×1.10` flat and `×1.15` for a hosted visit,
            // and neither one asked a single question about the club offering
            // them: they were paid for being the user. Together with the old
            // `.loyalty` branch that is the ×1.10 / ×1.15 / ×1.25 the audit
            // measured, against a maximum 12.4 % penalty for being bad, which is
            // how **a 2-15 user outbid a 14-3 AI club at 79 cents on the dollar**.
            //
            // The phenomenon underneath is real — a man does sign for a little
            // less to go where he was courted — so it survives at the size the
            // ruling priced it at rather than being deleted. 2 % for having a
            // front office he has actually spoken to, 4 % more for having walked
            // the building. The visit is additionally rate-limited by
            // `VisitTracker` (1/day, 3/week), so it is a scarce lever rather
            // than a standing multiplier.
            if bid.isPlayer {
                score *= 1.02
                if hostedVisit { score *= 1.04 }
                // The city, on the same scarce-lever footing as the visit above.
                // ±5 % at the extremes of `fanSupport`, which sits deliberately
                // between the 2 % "we actually courted him" pitch and the
                // `loserTax`, and far under `legacyVeteranPreference`'s ±25 %:
                // a full house tilts a close call and never outbids money.
                // `SigningInterestEngine.fanSupportBonus` is the same rule in
                // the meter the user reads, so the number he is shown and the
                // decision the engine makes cannot disagree.
                if let fanSupport {
                    score *= 1.0 + SigningInterestEngine.fanSupportBonus(fanSupport)
                }
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

    // MARK: - The Loser Tax (D1)

    /// How much one club's money is worth to a free agent, per what that club
    /// has been doing on Sundays. Above 1.0 for a winner, below 1.0 for a loser,
    /// exactly 1.0 at .500 and for a club with no record on file.
    ///
    /// # Why the SIGN, not the size, was the finding
    ///
    /// Before this, the entire penalty for being a bad club was one branch of
    /// the motivation switch — `.winning` players got `×(1 + winPct × 0.15)`,
    /// a **12.4 % spread between 0-17 and 17-0** and nothing at all for the
    /// other four motivations — while the user's club carried `×1.10` flat,
    /// `×1.15` for a visit and `×1.25` for a loyalty-motivated man regardless of
    /// its record. Net measured effect: **a 2-15 user outbid a 14-3 AI club at
    /// 79 cents on the dollar** (money-motivated, with a visit), or 61.8 cents
    /// for a loyalty-motivated one. The game had a discount for losing.
    ///
    /// Real free agents demand MORE to sign with a bad club, and the term is now
    /// universal, centred at .500 so it cuts both ways, and weighted by what the
    /// man is actually chasing. Worked at the audit's own headline case,
    /// money-motivated with a hosted visit: a 2-15 user is `×0.962` here and
    /// `×1.061` on the pitch = 1.020, against a 14-3 AI club's `×1.032` — so
    /// **the user now pays ≈101 cents on the dollar where he paid 79**, and
    /// ≈112 cents for a `.winning`-motivated man. The one case still running his
    /// way is the `.loyalty` man at ≈94 cents (≈97 without a visit) against
    /// **53.8 / 61.8** before, and that one is the hometown discount the ruling
    /// explicitly kept — at six percent instead of thirty-eight.
    ///
    /// # How this composes with D2(b), and why it is not a double count
    ///
    /// A club under the CBA's 89 % cash floor already pays a premium — but that
    /// one lives in `attemptSigning`, raises the **cash a club actually writes**,
    /// and runs on the AI-vs-AI bulk market, which never calls this function at
    /// all (see `legacyVeteranPreference`'s note). This one is a **perception**
    /// term on the shortlist a named free agent chooses from. The two therefore
    /// stack in the correct order rather than twice on the same quantity: a bad
    /// club is pushed to bid more money, and that money is then worth less to
    /// the man than the same money from a contender. Both together are what
    /// "bad clubs overpay in free agency" means.
    ///
    /// # What was rejected
    ///
    /// * **A flat league-wide weight.** It made a money-motivated man refuse a
    ///   cheque over a 4-13 record, which is not what money-motivated means.
    /// * **Gating the user's `×1.10` on his record instead of inverting.** The
    ///   queue's own option (F-14). It leaves a 12-5 user with a structural
    ///   bonus no AI club can earn, which is the asymmetry, not the size of it.
    ///
    /// - Parameter record: the suitor's season so far. `nil`, or fewer than four
    ///   games played, reads as 1.0 — March is not a referendum on a record
    ///   nobody has yet, and week 2 is not a record.
    static func loserTax(
        record: (wins: Int, losses: Int)?,
        motivation: Motivation
    ) -> Double {
        guard let record else { return 1.0 }
        let played = record.wins + record.losses
        guard played >= 4 else { return 1.0 }
        let winPct = Double(record.wins) / Double(played)
        // −0.5 (winless) … +0.5 (unbeaten), 0 at .500.
        let edge = winPct - 0.5
        return 1.0 + edge * loserTaxWeight(motivation)
    }

    /// Full 0-17-to-17-0 spread of the loser tax, by what the man is chasing.
    ///
    /// A `.winning` free agent is the one the record is nearly the whole
    /// decision for (24 %); a `.money` one still notices, because a losing club
    /// is a worse place to be paid (10 %) — the real market's "hazard pay" is
    /// visible but never decisive. `.fame` sits between them: losing is bad for
    /// a brand, but a big market is its own compensation and is priced
    /// separately by `mediaMarket.freeAgentAttraction`.
    private static func loserTaxWeight(_ motivation: Motivation) -> Double {
        switch motivation {
        case .winning: return 0.24
        case .fame:    return 0.14
        case .stats:   return 0.12
        case .money:   return 0.10
        case .loyalty: return 0.10
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
