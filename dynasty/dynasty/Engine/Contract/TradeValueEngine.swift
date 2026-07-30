import Foundation
import SwiftData

// MARK: - Trade Value Engine (R21)
//
// Modern trade valuation on the Jimmy Johnson pick-point scale:
// - Player value = exponential OVR curve × position multiplier × positional
//   age curve (RBs age fast, QBs slow) × contract-situation multiplier
//   (cheap multi-year deal is an asset, expiring/overpaid deals discount).
// - Pick value  = Jimmy Johnson chart, future-year picks discounted 20 %/year.
//
// Also owns:
// - The trade window rule (regular season through the Week 9 deadline + offseason).
// - AI accept / reject / counter logic (accept ≥ 105 %, reject < 90 %, else counter).
// - Weekly AI-initiated offers to the user (contenders buy, rebuilders sell).
// - Deadline-day AI-vs-AI trades that really move players and picks.
// - Roster-size, salary-cap, injury and no-trade-clause validation (CapMode-aware).
enum TradeValueEngine {

    // MARK: - Trade Window

    /// Last regular-season week during which trades may be made.
    /// The phase machine tags `.tradeDeadline` at the end of this week.
    ///
    /// Wave 1 moved this from 8 to 9 to match the real NFL deadline (Tuesday
    /// after week 9, i.e. past the halfway mark of the season) — the plan's
    /// finding S2. This is the single source of truth: the Trade Center's
    /// closed-window copy and the offer-expiry text already read it.
    ///
    /// PAIRED CHANGE: `WeekAdvancer` still gates its deadline pass on a
    /// hardcoded `if week == 8`; the Wave 1 phase work replaces that literal
    /// with this constant (and stops overwriting `.tradeDeadline` on the next
    /// line). Until it does, the AI-vs-AI deadline pass fires after week 8
    /// while the window stays open through week 9 — trades remain legal, the
    /// league's own flurry just lands a week early.
    static let deadlineWeek = 9

    /// Trading is open in every offseason phase and during the regular season
    /// up to and including the Week 8 deadline. Closed for playoffs and the
    /// Pro Bowl / Super Bowl ceremony weeks.
    static func isTradeWindowOpen(phase: SeasonPhase, week: Int) -> Bool {
        switch phase {
        case .regularSeason:
            return week <= deadlineWeek
        case .tradeDeadline:
            return true
        case .playoffs, .proBowl, .superBowl:
            return false
        default:
            return true
        }
    }

    // MARK: - Player Value Curve

    /// Trade value of a player on the Jimmy Johnson point scale.
    ///
    /// A 90+ OVR star is worth several times a 75 OVR starter:
    /// the base is `32 × 1.128^(OVR − 60)` (75 → ~194 pts, 90 → ~1188 pts,
    /// 99 → ~3510 pts, i.e. above the #1 overall pick before multipliers).
    static func playerTradeValue(player: Player) -> Int {
        let base = 32.0 * pow(1.128, Double(player.overall - 60))
        let value = base
            * positionMultiplier(player.position)
            * ageMultiplier(age: player.age, position: player.position)
            * contractMultiplier(player: player)
        return max(3, Int(value))
    }

    /// Premium positions carry more trade value at the same OVR.
    static func positionMultiplier(_ position: Position) -> Double {
        switch position {
        case .QB:               return 1.3
        case .WR, .DE:          return 1.1
        case .LT, .CB, .OLB:    return 1.05
        case .DT, .RT, .MLB,
             .FS, .SS, .TE:     return 1.0
        case .LG, .RG, .C:      return 0.95
        case .RB:               return 0.85
        case .FB:               return 0.6
        case .K, .P:            return 0.5
        }
    }

    /// Positional aging curve: value declines once a player passes the
    /// position's decline age; young players carry a small upside premium.
    /// RBs fall off hard after 26 while QBs hold value into their mid-30s.
    static func ageMultiplier(age: Int, position: Position) -> Double {
        let declineStart: Int
        let declinePerYear: Double
        switch position {
        case .QB:                       declineStart = 33; declinePerYear = 0.07
        case .RB, .FB:                  declineStart = 26; declinePerYear = 0.16
        case .WR:                       declineStart = 29; declinePerYear = 0.10
        case .TE:                       declineStart = 29; declinePerYear = 0.09
        case .LT, .LG, .C, .RG, .RT:    declineStart = 30; declinePerYear = 0.07
        case .DE, .DT:                  declineStart = 29; declinePerYear = 0.09
        case .OLB, .MLB:                declineStart = 28; declinePerYear = 0.09
        case .CB:                       declineStart = 28; declinePerYear = 0.12
        case .FS, .SS:                  declineStart = 28; declinePerYear = 0.10
        case .K, .P:                    declineStart = 36; declinePerYear = 0.04
        }

        if age > declineStart {
            return max(0.3, 1.0 - Double(age - declineStart) * declinePerYear)
        }
        if age <= 24 {
            // Youth premium: upside years still ahead.
            return min(1.15, 1.0 + Double(25 - age) * 0.05)
        }
        return 1.0
    }

    /// Contract situation multiplier:
    /// - Expiring deal (≤ 1 year left) or free agent → rental discount (×0.85).
    /// - Cheap multi-year deal (salary ≤ 70 % of market, 2+ years) → premium.
    /// - Overpaid (salary ≥ 130 % of market) → discount (×0.8).
    static func contractMultiplier(player: Player) -> Double {
        guard player.teamID != nil, player.contractYearsRemaining > 0 else {
            return 0.85
        }
        let market = max(1, ContractEngine.estimateMarketValue(player: player))
        let salaryRatio = Double(player.annualSalary) / Double(market)

        var multiplier = 1.0
        if player.contractYearsRemaining <= 1 {
            multiplier *= 0.85                          // deadline rental
        } else if salaryRatio <= 0.7 {
            // Bargain deal: +5 % per remaining year, capped at +20 %.
            multiplier *= min(1.2, 1.0 + 0.05 * Double(player.contractYearsRemaining))
        }
        if salaryRatio >= 1.3 {
            multiplier *= 0.8                           // overpaid contract
        }
        return max(0.6, min(1.25, multiplier))
    }

    // MARK: - Pick Value Curve

    /// Jimmy Johnson chart value with a 20 %/year discount for future picks.
    static func pickTradeValue(pick: DraftPick, currentSeason: Int) -> Int {
        let base = PickValueChart.points(forPick: pick.pickNumber)
        let yearsOut = max(0, pick.seasonYear - currentSeason)
        let discounted = Double(base) * pow(0.8, Double(yearsOut))
        return max(1, Int(discounted))
    }

    // MARK: - Proposal Valuation

    /// Total value each side of a proposal is sending, on the pick-point scale.
    /// "sending" = what the offering team gives up, "receiving" = what it gets.
    static func proposalValues(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int
    ) -> (sendingValue: Int, receivingValue: Int) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let sending =
            proposal.sendingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + playerTradeValue(player: $1) }
            +
            proposal.sendingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + pickTradeValue(pick: $1, currentSeason: currentSeason) }

        let receiving =
            proposal.receivingPlayers.compactMap { playerLookup[$0] }
                .reduce(0) { $0 + playerTradeValue(player: $1) }
            +
            proposal.receivingPicks.compactMap { pickLookup[$0] }
                .reduce(0) { $0 + pickTradeValue(pick: $1, currentSeason: currentSeason) }

        return (sending, receiving)
    }

    // MARK: - Partner Verdict (5-step, no exact numbers)

    /// How the trade partner feels about the proposal, from their perspective.
    enum PartnerVerdict: Int, CaseIterable {
        case loveIt, likeIt, onTheFence, wantMore, hangUp

        var label: String {
            switch self {
            case .loveIt:     return "They love it"
            case .likeIt:     return "They like it"
            case .onTheFence: return "They're on the fence"
            case .wantMore:   return "They'll want more"
            case .hangUp:     return "They'll hang up"
            }
        }

        var icon: String {
            switch self {
            case .loveIt:     return "star.circle.fill"
            case .likeIt:     return "hand.thumbsup.fill"
            case .onTheFence: return "arrow.left.arrow.right.circle.fill"
            case .wantMore:   return "plus.circle.fill"
            case .hangUp:     return "phone.down.fill"
            }
        }
    }

    /// Verdict from the AI partner's need-adjusted perspective.
    /// Assumes the AI team is the proposal's `receivingTeamID`.
    ///
    /// `contracts` lets the hard rules fold into the verdict so the preview the
    /// user reads equals the outcome he gets (plan §6 Wave 2.4 / G7): a package
    /// containing a no-trade-clause player reads `.hangUp` in the builder
    /// instead of "They love it" followed by a rejection alert.
    static func partnerVerdict(
        proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int,
        contracts: [Contract] = []
    ) -> PartnerVerdict {
        if noTradeClauseBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: [aiTeam],
            contracts: contracts
        ) != nil {
            return .hangUp
        }

        let (gives, gets) = aiPerspectiveValues(
            proposal: proposal,
            aiTeam: aiTeam,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: currentSeason
        )
        guard gives > 0 else { return gets > 0 ? .loveIt : .hangUp }
        let ratio = Double(gets) / Double(gives)
        if ratio >= 1.25 { return .loveIt }
        if ratio >= 1.05 { return .likeIt }
        if ratio >= 0.90 { return .onTheFence }
        if ratio >= 0.75 { return .wantMore }
        return .hangUp
    }

    // MARK: - AI Response (accept ≥105 %, reject <90 %, else counter)

    enum AIResponse {
        case accepted
        case rejected(reason: String)
        case countered(TradeProposal, message: String)
    }

    /// Deterministic, rule-based response so previews match outcomes.
    /// Assumes the AI team is the proposal's `receivingTeamID`.
    ///
    /// Pass `contracts` to enforce no-trade clauses; without them the clause is
    /// unreadable and the deal is priced on value alone (the pre-Wave-1
    /// behaviour, plan finding S3: the clause was negotiated, stored and never
    /// read by anything).
    static func respond(
        to proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int,
        contracts: [Contract] = []
    ) -> AIResponse {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })

        // Hard rule: a no-trade clause vetoes the deal from either side — the
        // user cannot ship his own protected star and cannot pry the AI's loose.
        if let blocker = noTradeClauseBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: [aiTeam],
            contracts: contracts
        ) {
            return .rejected(reason: blocker)
        }

        // Hard rule: an AI team never trades away its only quarterback.
        let aiRoster = allPlayers.filter { $0.teamID == aiTeam.id }
        let aiQBCount = aiRoster.filter { $0.position == .QB }.count
        for playerID in proposal.receivingPlayers {
            if let player = playerLookup[playerID],
               player.position == .QB, aiQBCount <= 1 {
                return .rejected(reason: "\(aiTeam.abbreviation) won't move their only quarterback.")
            }
        }

        let (gives, gets) = aiPerspectiveValues(
            proposal: proposal,
            aiTeam: aiTeam,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: currentSeason
        )

        guard gives > 0 || gets > 0 else {
            return .rejected(reason: "There's nothing on the table.")
        }
        guard gives > 0 else { return .accepted }   // free assets

        let ratio = Double(gets) / Double(gives)
        if ratio >= 1.05 {
            return .accepted
        }
        if ratio < 0.90 {
            return .rejected(reason: "\(aiTeam.abbreviation) hang up — the offer isn't close to their asking price.")
        }

        // 0.90 ..< 1.05 → counter-offer.
        if let counter = buildCounter(
            proposal: proposal,
            aiTeam: aiTeam,
            gives: gives,
            gets: gets,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: currentSeason
        ) {
            return .countered(counter.proposal, message: counter.message)
        }
        return .rejected(reason: "\(aiTeam.abbreviation) want more than you can offer right now.")
    }

    /// Need-adjusted values from the AI (receiving team) perspective:
    /// incoming players at a top-need position are worth 15 % more to them.
    private static func aiPerspectiveValues(
        proposal: TradeProposal,
        aiTeam: Team,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int
    ) -> (gives: Int, gets: Int) {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let aiRoster = allPlayers.filter { $0.teamID == aiTeam.id }
        let topNeeds = Set(DraftEngine.topTeamNeeds(roster: aiRoster, limit: 3))

        // AI gives up: proposal's receiving side.
        var gives = 0
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id] else { continue }
            gives += playerTradeValue(player: player)
        }
        for id in proposal.receivingPicks {
            guard let pick = pickLookup[id] else { continue }
            gives += pickTradeValue(pick: pick, currentSeason: currentSeason)
        }

        // AI gets: proposal's sending side, boosted for needed positions.
        var gets = 0
        for id in proposal.sendingPlayers {
            guard let player = playerLookup[id] else { continue }
            var value = playerTradeValue(player: player)
            if topNeeds.contains(player.position) {
                value = Int(Double(value) * 1.15)
            }
            gets += value
        }
        for id in proposal.sendingPicks {
            guard let pick = pickLookup[id] else { continue }
            gets += pickTradeValue(pick: pick, currentSeason: currentSeason)
        }

        return (gives, gets)
    }

    /// Builds a counter-offer that brings the AI to ~108 % of what it gives:
    /// 1) ask for one more of the user's picks, else
    /// 2) pull the smallest AI asset out of the deal.
    private static func buildCounter(
        proposal: TradeProposal,
        aiTeam: Team,
        gives: Int,
        gets: Int,
        allPlayers: [Player],
        allPicks: [DraftPick],
        currentSeason: Int
    ) -> (proposal: TradeProposal, message: String)? {
        let deficit = Int(Double(gives) * 1.08) - gets
        guard deficit > 0 else { return nil }

        // Option 1: request an additional pick from the offering team.
        let offeringTeamID = proposal.offeringTeamID
        let candidatePicks = allPicks
            .filter {
                $0.currentTeamID == offeringTeamID
                    && !$0.isComplete
                    && !proposal.sendingPicks.contains($0.id)
            }
            .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) <
                      pickTradeValue(pick: $1, currentSeason: currentSeason) }

        if let addition = candidatePicks.first(where: {
            pickTradeValue(pick: $0, currentSeason: currentSeason) >= deficit
        }) {
            var counter = proposal
            counter.sendingPicks.append(addition.id)
            let label = "\(addition.seasonYear) round \(addition.round) pick"
            return (counter, "\(aiTeam.abbreviation) counter: add your \(label) and it's a deal.")
        }

        // Option 2: AI removes its smallest outgoing asset instead.
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        var removables: [(id: UUID, isPlayer: Bool, value: Int, label: String)] = []
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id] else { continue }
            removables.append((id, true, playerTradeValue(player: player), player.fullName))
        }
        for id in proposal.receivingPicks {
            guard let pick = pickLookup[id] else { continue }
            removables.append((
                id, false,
                pickTradeValue(pick: pick, currentSeason: currentSeason),
                "their \(pick.seasonYear) round \(pick.round) pick"
            ))
        }

        let viable = removables
            .filter { candidate in
                let newGives = gives - candidate.value
                guard newGives > 0 else { return false }
                return Double(gets) / Double(newGives) >= 1.05
            }
            .sorted { $0.value < $1.value }

        if let removal = viable.first,
           removables.count > 1 {   // never counter down to an empty AI side
            var counter = proposal
            if removal.isPlayer {
                counter.receivingPlayers.removeAll { $0 == removal.id }
            } else {
                counter.receivingPicks.removeAll { $0 == removal.id }
            }
            return (counter, "\(aiTeam.abbreviation) counter: \(removal.label) stays out of the deal.")
        }

        return nil
    }

    // MARK: - Validation

    /// Returns human-readable blockers for a proposal (empty = valid).
    ///
    /// Checks, in order: no-trade clauses, injured players, roster-size bounds
    /// for both teams and — unless sandbox — that both teams stay under their
    /// salary cap after the swap, dead money included.
    ///
    /// Every rule here is symmetric on purpose (plan finding S5f / G7): the
    /// stored-offer invalidator (`isProposalStillValid`) already voided offers
    /// built on injured players, but the user's own proposals were never
    /// checked, so the builder happily shipped an injured player the AI would
    /// never have offered. Same for the clause: a rule the preview does not
    /// know about is a rule that reads as a bug.
    static func validationErrors(
        proposal: TradeProposal,
        allPlayers: [Player],
        teams: [Team],
        capMode: CapMode,
        contracts: [Contract] = []
    ) -> [String] {
        var errors: [String] = []
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let teamLookup = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        guard let offering = teamLookup[proposal.offeringTeamID],
              let receiving = teamLookup[proposal.receivingTeamID] else {
            return ["Unknown team in the proposal."]
        }

        let sendingPlayers = proposal.sendingPlayers.compactMap { playerLookup[$0] }
        let receivingPlayers = proposal.receivingPlayers.compactMap { playerLookup[$0] }

        // No-trade clause: a hard veto in both directions.
        if let blocker = noTradeClauseBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: teams,
            contracts: contracts
        ) {
            errors.append(blocker)
        }

        // Injured players cannot be traded — the same rule that voids a stored
        // AI offer the moment one of its assets goes down.
        for player in sendingPlayers where player.isInjured {
            errors.append("\(player.fullName) is injured — \(offering.abbreviation) can't trade him until he's cleared.")
        }
        for player in receivingPlayers where player.isInjured {
            errors.append("\(player.fullName) is injured — \(receiving.abbreviation) won't move him until he's cleared.")
        }

        // Roster-size bounds (keep both squads playable).
        let minRoster = 40
        let maxRoster = 75
        let offeringCount = allPlayers.filter { $0.teamID == offering.id }.count
            - sendingPlayers.count + receivingPlayers.count
        let receivingCount = allPlayers.filter { $0.teamID == receiving.id }.count
            + sendingPlayers.count - receivingPlayers.count

        if offeringCount < minRoster {
            errors.append("\(offering.abbreviation) roster would drop below \(minRoster) players.")
        }
        if receivingCount < minRoster {
            errors.append("\(receiving.abbreviation) roster would drop below \(minRoster) players.")
        }
        if offeringCount > maxRoster {
            errors.append("\(offering.abbreviation) roster would exceed \(maxRoster) players.")
        }
        if receivingCount > maxRoster {
            errors.append("\(receiving.abbreviation) roster would exceed \(maxRoster) players.")
        }

        // Salary-cap check (skipped entirely in sandbox mode). Uses the same
        // dead-money split `TradeEngine.executeTrade` applies, so a deal that
        // validates here cannot push a team over the cap once executed.
        if capMode != .sandbox {
            let offeringSide = capDeltas(for: sendingPlayers, contracts: contracts, capMode: capMode)
            let receivingSide = capDeltas(for: receivingPlayers, contracts: contracts, capMode: capMode)

            let offeringUsageAfter = offering.currentCapUsage
                - offeringSide.oldHit + offeringSide.deadCap + receivingSide.assumed
            let receivingUsageAfter = receiving.currentCapUsage
                - receivingSide.oldHit + receivingSide.deadCap + offeringSide.assumed

            if offeringUsageAfter > offering.salaryCap {
                let over = offeringUsageAfter - offering.salaryCap
                errors.append("\(offering.abbreviation) would be $\(formatThousands(over)) over the cap.")
            }
            if receivingUsageAfter > receiving.salaryCap {
                let over = receivingUsageAfter - receiving.salaryCap
                errors.append("\(receiving.abbreviation) would be $\(formatThousands(over)) over the cap.")
            }
        }

        return errors
    }

    /// Cap totals for one side of a trade: the cap hits leaving the books, the
    /// dead money staying behind, and the base salary the other team assumes.
    static func capDeltas(
        for players: [Player],
        contracts: [Contract],
        capMode: CapMode
    ) -> (oldHit: Int, deadCap: Int, assumed: Int) {
        let index = contractIndex(contracts)
        var oldHit = 0
        var deadCap = 0
        var assumed = 0
        for player in players {
            let split = CapManagementEngine.tradeCapSplit(
                player: player,
                contract: index[player.id],
                capMode: capMode
            )
            oldHit  += player.annualSalary
            deadCap += split.deadCap
            assumed += split.salaryAssumed
        }
        return (oldHit, deadCap, assumed)
    }

    /// Reason string when any player in the package carries an ACTIVE no-trade
    /// clause, otherwise `nil`.
    ///
    /// "Active" means the clause sits on the contract the player is currently
    /// playing under for his current team — a stale row from a previous deal
    /// never blocks anything. The clause was dead data before Wave 1 (finding
    /// S3): `ContractNegotiationEngine` hands it to ~50 % of 90+ OVR players
    /// who ask for it, stores it, and nothing ever read it back.
    ///
    /// `teams` only supplies the partner's abbreviation for the message; an
    /// unknown team degrades to "That team" rather than dropping the veto. The
    /// user-side message names no team on purpose, so it reads correctly from
    /// `respond`, which only knows the AI side.
    static func noTradeClauseBlocker(
        proposal: TradeProposal,
        allPlayers: [Player],
        teams: [Team],
        contracts: [Contract]
    ) -> String? {
        guard !contracts.isEmpty else { return nil }

        let index = contractIndex(contracts)
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let abbr: (UUID) -> String = { id in
            teams.first { $0.id == id }?.abbreviation ?? "That team"
        }

        func isProtected(_ player: Player) -> Bool {
            guard let contract = index[player.id] else { return false }
            return contract.noTradeClause && contract.teamID == player.teamID
        }

        for id in proposal.sendingPlayers {
            guard let player = playerLookup[id], isProtected(player) else { continue }
            return "\(player.fullName) holds a no-trade clause — he has to waive it before he can be included in any deal."
        }
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id], isProtected(player) else { continue }
            return "\(abbr(proposal.receivingTeamID)) can't move \(player.fullName) — his no-trade clause blocks any deal."
        }
        return nil
    }

    /// True when this player's current deal carries an active no-trade clause.
    /// The offer builders call it so the AI never SHOPS a protected player and
    /// never asks for one — an offer the validator would veto anyway is worse
    /// than no offer at all.
    static func hasActiveNoTradeClause(player: Player, contracts: [Contract]) -> Bool {
        guard !contracts.isEmpty else { return false }
        guard let contract = contracts.first(where: { $0.playerID == player.id }) else { return false }
        return contract.noTradeClause && contract.teamID == player.teamID
    }

    /// First contract per player, keyed by `playerID`. Contract rows are only
    /// minted for realistic-mode signings, so most players have none.
    private static func contractIndex(_ contracts: [Contract]) -> [UUID: Contract] {
        var index: [UUID: Contract] = [:]
        for contract in contracts where index[contract.playerID] == nil {
            index[contract.playerID] = contract
        }
        return index
    }

    /// A stored pending offer is still valid only while every asset is still
    /// owned by the team that is supposed to send it.
    static func isProposalStillValid(
        _ proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick]
    ) -> Bool {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        for id in proposal.sendingPlayers {
            guard let player = playerLookup[id],
                  player.teamID == proposal.offeringTeamID, !player.isInjured else { return false }
        }
        for id in proposal.receivingPlayers {
            guard let player = playerLookup[id],
                  player.teamID == proposal.receivingTeamID else { return false }
        }
        for id in proposal.sendingPicks {
            guard let pick = pickLookup[id],
                  pick.currentTeamID == proposal.offeringTeamID, !pick.isComplete else { return false }
        }
        for id in proposal.receivingPicks {
            guard let pick = pickLookup[id],
                  pick.currentTeamID == proposal.receivingTeamID, !pick.isComplete else { return false }
        }
        return !(proposal.sendingPlayers.isEmpty && proposal.sendingPicks.isEmpty)
    }

    // MARK: - Weekly AI-Initiated Offers

    /// A generated AI offer plus the explanation shown to the user.
    struct AIOffer {
        let proposal: TradeProposal
        let offeringTeamAbbr: String
        let subject: String
        let rationale: String
    }

    /// Builds one AI-initiated offer targeting the user's team, or nil when
    /// no believable deal exists this week. Caller owns the dice roll for
    /// whether an offer is attempted at all (~15 %/week).
    ///
    /// - Contenders (wins − losses ≥ 2) BUY: they offer picks (plus a filler
    ///   player if needed) for a good player at one of their need positions.
    /// - Rebuilders (losses − wins ≥ 2) SELL: they offer a veteran at one of
    ///   the user's need positions and ask for the user's picks.
    ///
    /// `contracts` is optional so the weekly `WeekAdvancer` roll keeps
    /// compiling untouched, but SHOULD be supplied: without it the generator
    /// cannot see no-trade clauses and may build an offer for a protected
    /// player that the Trade Center then refuses to execute (preview ≡ outcome,
    /// plan G7). One-line fix at the call site: pass the fetched `[Contract]`.
    static func generateWeeklyAIOffer(
        userTeam: Team,
        allTeams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        capMode: CapMode,
        currentSeason: Int,
        contracts: [Contract] = []
    ) -> AIOffer? {
        let aiTeams = allTeams.filter { $0.id != userTeam.id }.shuffled()
        let userRoster = allPlayers.filter { $0.teamID == userTeam.id }
        let userNeeds = Set(DraftEngine.topTeamNeeds(roster: userRoster, limit: 4))

        for aiTeam in aiTeams {
            let diff = aiTeam.wins - aiTeam.losses
            if diff >= 2 {
                if let offer = buildContenderBuyOffer(
                    contender: aiTeam, userTeam: userTeam, userRoster: userRoster,
                    allPlayers: allPlayers, allPicks: allPicks,
                    allTeams: allTeams, capMode: capMode, currentSeason: currentSeason,
                    contracts: contracts
                ) {
                    return offer
                }
            } else if diff <= -2 {
                if let offer = buildRebuilderSellOffer(
                    rebuilder: aiTeam, userTeam: userTeam, userNeeds: userNeeds,
                    allPlayers: allPlayers, allPicks: allPicks,
                    allTeams: allTeams, capMode: capMode, currentSeason: currentSeason,
                    contracts: contracts
                ) {
                    return offer
                }
            }
        }
        return nil
    }

    /// Contender buys: offers its picks (plus a filler player if the picks
    /// fall short) for a user player at one of the contender's need positions.
    private static func buildContenderBuyOffer(
        contender: Team,
        userTeam: Team,
        userRoster: [Player],
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        currentSeason: Int,
        contracts: [Contract]
    ) -> AIOffer? {
        let contenderRoster = allPlayers.filter { $0.teamID == contender.id }
        let needs = Set(DraftEngine.topTeamNeeds(roster: contenderRoster, limit: 4))
        let userQBCount = userRoster.filter { $0.position == .QB }.count

        // Targets: healthy, good players at the contender's need positions.
        // Never the user's only QB.
        let targets = userRoster
            .filter { player in
                guard player.overall >= 74, !player.isInjured, needs.contains(player.position) else { return false }
                if player.position == .QB && userQBCount <= 1 { return false }
                // Never call about a player his contract protects.
                if hasActiveNoTradeClause(player: player, contracts: contracts) { return false }
                return true
            }
            .sorted { playerTradeValue(player: $0) > playerTradeValue(player: $1) }

        guard let target = targets.prefix(3).randomElement() else { return nil }
        let targetValue = playerTradeValue(player: target)

        // Build the pick package (max 3 picks, aim slightly above value).
        let goal = Int(Double(targetValue) * 1.05)
        var packagePicks: [DraftPick] = []
        var packageValue = 0
        let contenderPicks = allPicks
            .filter { $0.currentTeamID == contender.id && !$0.isComplete }
            .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) >
                      pickTradeValue(pick: $1, currentSeason: currentSeason) }
        for pick in contenderPicks {
            guard packageValue < goal, packagePicks.count < 3 else { break }
            let value = pickTradeValue(pick: pick, currentSeason: currentSeason)
            // Skip picks that would blow far past the goal on their own.
            if packageValue == 0 && Double(value) > Double(goal) * 1.35 { continue }
            packagePicks.append(pick)
            packageValue += value
        }

        // Filler player if picks fall short.
        var packagePlayers: [Player] = []
        if Double(packageValue) < Double(targetValue) * 0.95 {
            let gap = targetValue - packageValue
            let filler = contenderRoster
                .filter { !$0.isInjured && $0.overall >= 65 && $0.overall <= 76 && $0.position != .QB }
                .min { abs(playerTradeValue(player: $0) - gap) < abs(playerTradeValue(player: $1) - gap) }
            if let filler {
                packagePlayers.append(filler)
                packageValue += playerTradeValue(player: filler)
            }
        }

        let ratio = Double(packageValue) / Double(max(1, targetValue))
        guard ratio >= 0.95 && ratio <= 1.3 else { return nil }

        let proposal = TradeProposal(
            offeringTeamID: contender.id,
            receivingTeamID: userTeam.id,
            sendingPlayers: packagePlayers.map(\.id),
            receivingPlayers: [target.id],
            sendingPicks: packagePicks.map(\.id),
            receivingPicks: []
        )
        guard validationErrors(
            proposal: proposal, allPlayers: allPlayers, teams: allTeams,
            capMode: capMode, contracts: contracts
        ).isEmpty else { return nil }

        let assetText = offerAssetText(
            players: packagePlayers, picks: packagePicks, currentSeason: currentSeason
        )
        return AIOffer(
            proposal: proposal,
            offeringTeamAbbr: contender.abbreviation,
            subject: "\(contender.abbreviation) call about \(target.lastName)",
            rationale: "\(contender.fullName) (\(contender.record)) are pushing for the playoffs and want \(target.fullName) (\(target.position.rawValue), \(target.overall) OVR) to fill a hole at \(target.position.rawValue). Their offer: \(assetText)."
        )
    }

    /// Rebuilder sells: offers a veteran at one of the user's need positions
    /// and asks for the user's draft picks in return.
    private static func buildRebuilderSellOffer(
        rebuilder: Team,
        userTeam: Team,
        userNeeds: Set<Position>,
        allPlayers: [Player],
        allPicks: [DraftPick],
        allTeams: [Team],
        capMode: CapMode,
        currentSeason: Int,
        contracts: [Contract]
    ) -> AIOffer? {
        let rebuilderRoster = allPlayers.filter { $0.teamID == rebuilder.id }

        // Veteran on the block, ideally at a position the user needs.
        let vets = rebuilderRoster
            .filter { $0.age >= 28 && $0.overall >= 75 && !$0.isInjured && $0.position != .QB }
            // A protected veteran is not on the block.
            .filter { !hasActiveNoTradeClause(player: $0, contracts: contracts) }
            .sorted { playerTradeValue(player: $0) > playerTradeValue(player: $1) }
        let preferred = vets.filter { userNeeds.contains($0.position) }
        guard let vet = (preferred.first ?? vets.first) else { return nil }
        let vetValue = playerTradeValue(player: vet)

        // Ask: user picks totalling ~90-105 % of the vet's value (max 2 picks).
        var askPicks: [DraftPick] = []
        var askValue = 0
        let userPicks = allPicks
            .filter { $0.currentTeamID == userTeam.id && !$0.isComplete }
            .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) >
                      pickTradeValue(pick: $1, currentSeason: currentSeason) }
        for pick in userPicks {
            guard Double(askValue) < Double(vetValue) * 0.9, askPicks.count < 2 else { break }
            let value = pickTradeValue(pick: pick, currentSeason: currentSeason)
            if askValue == 0 && Double(value) > Double(vetValue) * 1.2 { continue }
            askPicks.append(pick)
            askValue += value
        }
        guard !askPicks.isEmpty else { return nil }

        let ratio = Double(askValue) / Double(max(1, vetValue))
        guard ratio >= 0.8 && ratio <= 1.1 else { return nil }

        let proposal = TradeProposal(
            offeringTeamID: rebuilder.id,
            receivingTeamID: userTeam.id,
            sendingPlayers: [vet.id],
            receivingPlayers: [],
            sendingPicks: [],
            receivingPicks: askPicks.map(\.id)
        )
        guard validationErrors(
            proposal: proposal, allPlayers: allPlayers, teams: allTeams,
            capMode: capMode, contracts: contracts
        ).isEmpty else { return nil }

        let askText = offerAssetText(players: [], picks: askPicks, currentSeason: currentSeason)
        return AIOffer(
            proposal: proposal,
            offeringTeamAbbr: rebuilder.abbreviation,
            subject: "\(rebuilder.abbreviation) shopping \(vet.lastName)",
            rationale: "\(rebuilder.fullName) (\(rebuilder.record)) are selling. They're offering veteran \(vet.position.rawValue) \(vet.fullName) (\(vet.overall) OVR, age \(vet.age)) and asking for \(askText)."
        )
    }

    /// Inbox message for a freshly generated AI offer.
    static func offerInboxMessage(offer: AIOffer, week: Int, season: Int) -> InboxMessage {
        InboxMessage(
            sender: .scout(name: "Pro Personnel Dept."),
            subject: offer.subject,
            body: """
            Coach,

            \(offer.rationale)

            The offer is waiting in the Trade Center — you can accept it, decline it, or use it as a starting point and negotiate. It expires at the Week \(deadlineWeek) trade deadline.

            Pro Personnel
            """,
            date: "Week \(week), Season \(season)",
            category: .tradeOffer,
            actionRequired: true,
            actionDestination: .trades,
            attachments: [
                MessageAttachment(title: "Open Trade Center", destination: .trades)
            ]
        )
    }

    // MARK: - Deadline Day AI-vs-AI Trades

    /// Summary of an executed league trade for news/inbox rendering.
    struct LeagueTradeSummary {
        let buyerAbbr: String
        let buyerName: String
        let sellerAbbr: String
        let sellerName: String
        let playerName: String
        let playerPosition: Position
        let playerOverall: Int
        let playerID: UUID
        let buyerTeamID: UUID
        let pickDescription: String
    }

    /// Executes 2-4 believable AI-vs-AI deadline trades (contender buys a
    /// veteran from a rebuilder for picks, value-validated to 0.85-1.2×) and
    /// really moves the players/picks. The user's team never participates.
    static func executeDeadlineTrades(
        userTeamID: UUID?,
        teams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        capMode: CapMode,
        currentSeason: Int,
        modelContext: ModelContext
    ) -> [LeagueTradeSummary] {
        let aiTeams = teams.filter { $0.id != userTeamID }
        var contenders = aiTeams.filter { $0.wins - $0.losses >= 2 }.shuffled()
        var sellers    = aiTeams.filter { $0.losses - $0.wins >= 2 }.shuffled()

        var summaries: [LeagueTradeSummary] = []
        let targetCount = Int.random(in: 2...4)

        // Contracts are fetched here rather than threaded in from `WeekAdvancer`
        // so this pass enforces no-trade clauses and dead-money cap limits with
        // no change to its call site.
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>())) ?? []

        // Track ownership changes locally so consecutive trades stay coherent.
        var pickOwner: [UUID: UUID] = Dictionary(uniqueKeysWithValues: allPicks.map { ($0.id, $0.currentTeamID) })

        while summaries.count < targetCount, let seller = sellers.popLast() {
            let sellerRoster = allPlayers.filter { $0.teamID == seller.id }
            let vets = sellerRoster
                .filter { $0.age >= 27 && $0.overall >= 75 && !$0.isInjured && $0.position != .QB }
                .filter { !hasActiveNoTradeClause(player: $0, contracts: contracts) }
                .sorted { playerTradeValue(player: $0) > playerTradeValue(player: $1) }
            guard let vet = vets.prefix(3).randomElement() else { continue }
            let vetValue = playerTradeValue(player: vet)

            // Find a contender that needs the position and can pay in picks.
            var matched = false
            for (index, buyer) in contenders.enumerated() {
                let buyerRoster = allPlayers.filter { $0.teamID == buyer.id }
                let buyerNeeds = Set(DraftEngine.topTeamNeeds(roster: buyerRoster, limit: 4))
                guard buyerNeeds.contains(vet.position) else { continue }

                var packagePicks: [DraftPick] = []
                var packageValue = 0
                let buyerPicks = allPicks
                    .filter { pickOwner[$0.id] == buyer.id && !$0.isComplete }
                    .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) >
                              pickTradeValue(pick: $1, currentSeason: currentSeason) }
                for pick in buyerPicks {
                    guard Double(packageValue) < Double(vetValue) * 0.9, packagePicks.count < 3 else { break }
                    let value = pickTradeValue(pick: pick, currentSeason: currentSeason)
                    if packageValue == 0 && Double(value) > Double(vetValue) * 1.2 { continue }
                    packagePicks.append(pick)
                    packageValue += value
                }
                guard !packagePicks.isEmpty else { continue }

                let ratio = Double(packageValue) / Double(max(1, vetValue))
                guard ratio >= 0.85 && ratio <= 1.2 else { continue }

                let proposal = TradeProposal(
                    offeringTeamID: seller.id,
                    receivingTeamID: buyer.id,
                    sendingPlayers: [vet.id],
                    receivingPlayers: [],
                    sendingPicks: [],
                    receivingPicks: packagePicks.map(\.id)
                )
                guard validationErrors(
                    proposal: proposal, allPlayers: allPlayers, teams: teams,
                    capMode: capMode, contracts: contracts
                ).isEmpty else { continue }

                // Wave 0 ledger. `week`/`phase` are stamped from the deadline
                // constants rather than the live career: this pass runs only at
                // the end of `deadlineWeek`, and `.tradeDeadline` is the phase
                // the deal semantically belongs to even though `WeekAdvancer`
                // reassigns `.regularSeason` on the next line (finding S2).
                TradeEngine.executeTrade(
                    proposal: proposal,
                    allPlayers: allPlayers,
                    allPicks: allPicks,
                    capMode: capMode,
                    ledger: TradeLedger.Context(
                        kind: .aiDeadline,
                        season: currentSeason,
                        week: deadlineWeek,
                        phase: .tradeDeadline
                    ),
                    modelContext: modelContext
                )
                for pick in packagePicks { pickOwner[pick.id] = seller.id }

                summaries.append(LeagueTradeSummary(
                    buyerAbbr: buyer.abbreviation,
                    buyerName: buyer.fullName,
                    sellerAbbr: seller.abbreviation,
                    sellerName: seller.fullName,
                    playerName: vet.fullName,
                    playerPosition: vet.position,
                    playerOverall: vet.overall,
                    playerID: vet.id,
                    buyerTeamID: buyer.id,
                    pickDescription: offerAssetText(players: [], picks: packagePicks, currentSeason: currentSeason)
                ))

                contenders.remove(at: index)   // one deadline splash per buyer
                matched = true
                break
            }
            _ = matched
        }

        return summaries
    }

    /// News item for one executed league trade.
    static func newsItem(for trade: LeagueTradeSummary, week: Int, season: Int) -> NewsItem {
        NewsItem(
            headline: "Deadline deal: \(trade.buyerAbbr) land \(trade.playerPosition.rawValue) \(trade.playerName)",
            body: "\(trade.buyerName) acquired \(trade.playerPosition.rawValue) \(trade.playerName) (\(trade.playerOverall) OVR) from \(trade.sellerName) in exchange for \(trade.pickDescription). The \(trade.sellerAbbr) front office called it \"a move for the future\", while \(trade.buyerAbbr) clearly believe they are one piece away.",
            category: .trade,
            week: week,
            season: season,
            relatedTeamID: trade.buyerTeamID,
            relatedPlayerID: trade.playerID,
            sentiment: .neutral
        )
    }

    /// League-office inbox roundup of deadline day.
    static func deadlineRoundupMessage(
        trades: [LeagueTradeSummary],
        week: Int,
        season: Int
    ) -> InboxMessage {
        let lines = trades
            .map { "• \($0.buyerAbbr) acquire \($0.playerPosition.rawValue) \($0.playerName) from \($0.sellerAbbr) for \($0.pickDescription)" }
            .joined(separator: "\n")
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Trade Deadline Day: \(trades.count) deals across the league",
            body: """
            The trade deadline has passed. Official transactions:

            \(lines)

            All trades are final. The trade window reopens in the offseason.

            NFL League Office
            """,
            date: "Week \(week), Season \(season)",
            category: .leagueNotice,
            actionDestination: .news
        )
    }

    // MARK: - Forced Trade (holdout capitulation)

    /// A ready-to-execute package for shipping one specific player out.
    struct ForcedTradePackage {
        let proposal: TradeProposal
        let partner: Team
        /// "a 2027 round 2 pick and CB Ray Voss (72 OVR)" — for inbox/news copy.
        let returnDescription: String
    }

    /// Prices a fair return for a player the front office has decided to move
    /// and picks the best-fit partner for him.
    ///
    /// Used by `HoldoutEngine.forceTrade`, which used to mark a holdout
    /// `.traded` while the player stayed on the roster (plan finding S3). The
    /// return is deliberately aimed slightly BELOW the player's market value
    /// (0.85–1.0×): a team trading a disgruntled star under duress does not get
    /// full price, and the discount is what makes an AI GM say yes.
    ///
    /// Partner order is best-fit first: teams with a top-4 positional need,
    /// then the rest, so the player lands somewhere he would actually start.
    /// Every candidate package is run through `validationErrors` AND `respond`
    /// before it is offered, so the caller can execute the returned proposal
    /// without re-asking — preview ≡ outcome (plan G7).
    ///
    /// Returns `nil` when no partner can put together a believable package
    /// (e.g. no tradable picks exist yet — finding S1); the caller must treat
    /// that as "no market" and leave the roster alone.
    static func buildForcedTradePackage(
        player: Player,
        sellingTeam: Team,
        allTeams: [Team],
        allPlayers: [Player],
        allPicks: [DraftPick],
        contracts: [Contract],
        capMode: CapMode,
        currentSeason: Int
    ) -> ForcedTradePackage? {
        guard player.teamID == sellingTeam.id else { return nil }

        let value = playerTradeValue(player: player)
        guard value > 0 else { return nil }

        // Best-fit first: does the buyer have a top-4 need at his position?
        let candidates = allTeams
            .filter { $0.id != sellingTeam.id }
            .map { team -> (team: Team, needsHim: Bool) in
                let roster = allPlayers.filter { $0.teamID == team.id }
                let needs = Set(DraftEngine.topTeamNeeds(roster: roster, limit: 4))
                return (team, needs.contains(player.position))
            }
            .sorted { lhs, rhs in
                if lhs.needsHim != rhs.needsHim { return lhs.needsHim }
                return lhs.team.availableCap > rhs.team.availableCap
            }

        for candidate in candidates {
            let buyer = candidate.team
            let buyerRoster = allPlayers.filter { $0.teamID == buyer.id }

            // Picks first, best-first, capped at 3 — a holdout return is picks
            // and a young body, not a franchise-altering haul.
            let goal = Int(Double(value) * 0.95)
            var returnPicks: [DraftPick] = []
            var returnValue = 0
            let buyerPicks = allPicks
                .filter { $0.currentTeamID == buyer.id && !$0.isComplete }
                .sorted { pickTradeValue(pick: $0, currentSeason: currentSeason) >
                          pickTradeValue(pick: $1, currentSeason: currentSeason) }
            for pick in buyerPicks {
                guard returnValue < goal, returnPicks.count < 3 else { break }
                let pickValue = pickTradeValue(pick: pick, currentSeason: currentSeason)
                if returnValue == 0 && Double(pickValue) > Double(value) * 1.1 { continue }
                returnPicks.append(pick)
                returnValue += pickValue
            }

            // Young player to close the gap when the picks fall short.
            var returnPlayers: [Player] = []
            if returnValue < Int(Double(value) * 0.85) {
                let gap = Int(Double(value) * 0.95) - returnValue
                let filler = buyerRoster
                    .filter {
                        !$0.isInjured && $0.position != .QB
                            && $0.overall >= 60 && $0.overall <= 80
                            && !hasActiveNoTradeClause(player: $0, contracts: contracts)
                    }
                    .min { abs(playerTradeValue(player: $0) - gap) < abs(playerTradeValue(player: $1) - gap) }
                if let filler {
                    returnPlayers.append(filler)
                    returnValue += playerTradeValue(player: filler)
                }
            }

            guard returnValue > 0 else { continue }
            let ratio = Double(returnValue) / Double(value)
            guard ratio >= 0.6 && ratio <= 1.0 else { continue }

            let proposal = TradeProposal(
                offeringTeamID: sellingTeam.id,
                receivingTeamID: buyer.id,
                sendingPlayers: [player.id],
                receivingPlayers: returnPlayers.map(\.id),
                sendingPicks: [],
                receivingPicks: returnPicks.map(\.id)
            )

            guard validationErrors(
                proposal: proposal, allPlayers: allPlayers, teams: allTeams,
                capMode: capMode, contracts: contracts
            ).isEmpty else { continue }

            guard case .accepted = respond(
                to: proposal, aiTeam: buyer, allPlayers: allPlayers,
                allPicks: allPicks, currentSeason: currentSeason, contracts: contracts
            ) else { continue }

            return ForcedTradePackage(
                proposal: proposal,
                partner: buyer,
                returnDescription: offerAssetText(
                    players: returnPlayers, picks: returnPicks, currentSeason: currentSeason
                )
            )
        }

        return nil
    }

    // MARK: - Helpers

    /// "a 2026 round 1 pick, a 2027 round 3 pick and WR John Smith"
    private static func offerAssetText(
        players: [Player],
        picks: [DraftPick],
        currentSeason: Int
    ) -> String {
        var parts: [String] = picks.map { "a \($0.seasonYear) round \($0.round) pick" }
        parts.append(contentsOf: players.map { "\($0.position.rawValue) \($0.fullName) (\($0.overall) OVR)" })
        guard !parts.isEmpty else { return "nothing" }
        if parts.count == 1 { return parts[0] }
        let head = parts.dropLast().joined(separator: ", ")
        return "\(head) and \(parts.last!)"
    }

    private static func formatThousands(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        return millions >= 1.0 ? String(format: "%.1fM", millions) : "\(thousands)K"
    }
}
