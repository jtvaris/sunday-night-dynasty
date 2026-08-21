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

/// The one primitive that MOVES trade assets.
///
/// Wave 2 cleanup (plan §6 Wave 5, pulled forward because Wave 2 replaced the
/// code): this type used to ship its own parallel trade brain —
/// `evaluateTradeValue` (players priced by `ContractEngine.estimateMarketValue`,
/// picks by the linear `DraftEngine.pickValue`), `aiWouldAccept` (a 90 % ratio
/// test), `generateAITradeOffers` and a duplicate `evaluateTeamNeeds` depth
/// table. All four were DEAD (plan §2: "three parallel trade brains ship in the
/// binary; only one runs") and all four are now deleted: `TradeValueEngine` is
/// the single valuation + AI authority, on the Jimmy Johnson scale the UI and
/// the draft room already speak.
enum TradeEngine {

    // MARK: - Execute Trade

    /// Dead money each side ate to get the deal done, in thousands.
    /// Returned so the caller can report it (inbox notice, cap screens) without
    /// re-deriving the split.
    struct TradeCapOutcome {
        /// Dead cap the OFFERING team keeps for the players it sent away.
        var offeringDeadCap: Int = 0
        /// Dead cap the RECEIVING team keeps for the players it sent away.
        var receivingDeadCap: Int = 0
        /// The ledger row this execution wrote, or `nil` when the trade could not
        /// be applied (unknown team).
        ///
        /// Handed back so the caller can announce the deal without re-deriving
        /// anything: `TradeNewsFactory.announce(record:…)` is called at EVERY
        /// execution site (Wave 2 requirement — every trade in the league, the
        /// user's and the other 31 clubs', has to surface as news and, when it
        /// concerns him, as an inbox message).
        var record: TradeRecord?

        var totalDeadCap: Int { offeringDeadCap + receivingDeadCap }

        /// Dead cap the USER's club is left holding, given which side of the
        /// proposal he was on.
        func deadCap(userIsOfferingTeam: Bool) -> Int {
            userIsOfferingTeam ? offeringDeadCap : receivingDeadCap
        }

        /// The one dead-money sentence every user-facing receipt quotes, or `nil`
        /// when the deal left nothing behind.
        ///
        /// F-49: there were two receipts for the same event and which one the
        /// user got depended on which SCREEN he executed from — the Trade Center
        /// quoted the dead money and the shared factory said only "roster and cap
        /// adjustments have been processed", so the draft room and the holdout
        /// path got the silent one. This is the line itself, in the engine layer
        /// that computes the number, so no surface can disclose a different
        /// amount or forget to disclose it at all.
        func deadCapLine(userIsOfferingTeam: Bool) -> String? {
            let dead = deadCap(userIsOfferingTeam: userIsOfferingTeam)
            guard dead > 0 else { return nil }
            let millions = Double(dead) / 1000.0
            let formatted = millions >= 10
                ? String(format: "$%.0fM", millions)
                : String(format: "$%.1fM", millions)
            return "Dead money retained: \(formatted) — the signing-bonus proration stays on our cap."
        }
    }

    /// Applies a trade proposal to the data store:
    /// - Writes the `TradeRecord` ledger row (Wave 0 instrumentation).
    /// - Swaps `teamID` on each player and re-points his `Contract` row.
    /// - Swaps `currentTeamID` on each draft pick.
    /// - Updates `currentCapUsage` on both teams, dead money included.
    ///
    /// `ledger` is required, not optional, on purpose: this is the one
    /// primitive that moves trade assets, so making the calendar/provenance
    /// stamp part of its signature means no execution path can move players
    /// without leaving a measurable row behind (`docs/TRADE_OVERHAUL_PLAN.md`
    /// finding S9). The row is written before the mutation so the asset
    /// summaries describe the deal as it was struck.
    ///
    /// Wave 1 cap truth (finding S3): salary no longer moves 1:1. The signing-
    /// bonus proration accelerates onto the team that paid it
    /// (`CapManagementEngine.tradeCapSplit`, the same model as a release), the
    /// acquiring team takes only the base salary, and the traded player's
    /// `Contract` row follows him with the bonus stripped so next season's cap
    /// hits and any later cut price him correctly on his new team.
    ///
    /// Wave 4 (task #26) adds the calendar to that split: the base salary is
    /// prorated by how much of the league year is still unpaid, which the
    /// `ledger` stamp already knows (`phase` + `week`). Deriving it there rather
    /// than from a new parameter is deliberate — the same argument as making
    /// `ledger` mandatory. A caller cannot move a player without saying WHEN,
    /// so no execution path can accidentally charge a deadline rental twelve
    /// months of salary.
    @discardableResult
    static func executeTrade(
        proposal: TradeProposal,
        allPlayers: [Player],
        allPicks: [DraftPick],
        capMode: CapMode,
        ledger: TradeLedger.Context,
        modelContext: ModelContext
    ) -> TradeCapOutcome {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        // Fetch both teams
        let offeringTeamID  = proposal.offeringTeamID
        let receivingTeamID = proposal.receivingTeamID

        let cid = WeekAdvancer.activeCareerID
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        let allTeams = (try? modelContext.fetch(teamDescriptor)) ?? []
        let teamLookup = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        guard let offeringTeam  = teamLookup[offeringTeamID],
              let receivingTeam = teamLookup[receivingTeamID]
        else { return TradeCapOutcome() }

        // Detailed contracts are fetched here rather than passed in so EVERY
        // execution path (Trade Center, deadline pass, forced holdout trade)
        // gets identical cap treatment — a caller cannot forget them.
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        var contractByPlayer: [UUID: Contract] = [:]
        for contract in contracts where contractByPlayer[contract.playerID] == nil {
            contractByPlayer[contract.playerID] = contract
        }

        // --- Ledger row, before any asset moves ---
        let record = TradeLedger.record(
            proposal: proposal,
            context: ledger,
            allPlayers: allPlayers,
            allPicks: allPicks,
            modelContext: modelContext
        )

        var outcome = TradeCapOutcome()
        outcome.record = record

        // Task #26: how much of the league year the acquiring club still owes.
        let remaining = CapManagementEngine.leagueYearRemaining(
            phase: ledger.phase,
            week: ledger.week
        )

        // --- Move sending players: offering → receiving ---
        for playerID in proposal.sendingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            let dead = movePlayer(
                player,
                from: offeringTeam,
                to: receivingTeam,
                contract: contractByPlayer[playerID],
                capMode: capMode,
                leagueYearRemaining: remaining
            )
            outcome.offeringDeadCap += dead
        }

        // --- Move receiving players: receiving → offering ---
        for playerID in proposal.receivingPlayers {
            guard let player = playerLookup[playerID] else { continue }
            let dead = movePlayer(
                player,
                from: receivingTeam,
                to: offeringTeam,
                contract: contractByPlayer[playerID],
                capMode: capMode,
                leagueYearRemaining: remaining
            )
            outcome.receivingDeadCap += dead
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

        recordOrganisationalLearning(record: record, kind: ledger.kind)

        return outcome
    }

    /// D7-A: what the two front offices learned by doing this deal.
    ///
    /// It lives inside `executeTrade` for the same reason the ledger row does —
    /// this is the ONE primitive that moves trade assets, so putting the learning
    /// here means no execution path can move players without both clubs coming
    /// away knowing each other a little better. The Trade Center, the draft room,
    /// the deadline pass and the holdout capitulation all get it for free.
    ///
    /// Two separate things are recorded and they are not the same thing:
    ///
    /// * **Contact** fills the `ScoutingDossier`, in BOTH directions and for every
    ///   pair including two AI clubs. It is what narrows the valuation fog: a
    ///   club you deal with every deadline becomes legible, a club you have never
    ///   phoned stays a stranger.
    /// * **Reputation** is recorded only when the USER is one of the two clubs,
    ///   because he is the only actor who can declare one identity and behave
    ///   like another (see `TradeReputationRegistry`). Which side he was on comes
    ///   from the ledger kind rather than from a new parameter: `.userProposal`
    ///   means he built the deal and is the row's initiator, `.aiWeeklyOffer`
    ///   means a club called him and he is the partner.
    ///
    /// Draft-weekend swaps are deliberately NOT scored for reputation: they are
    /// pick-for-pick business priced off the same public chart both sides are
    /// reading, so they say almost nothing about how a GM values things. They
    /// still count as contact.
    private static func recordOrganisationalLearning(
        record: TradeRecord?,
        kind: TradeRecordKind
    ) {
        guard let record else { return }

        TradeValueEngine.ScoutingDossier.recordMutualContact(
            record.initiatorTeamID,
            record.partnerTeamID,
            discipline: .frontOffice
        )

        switch kind {
        case .userProposal:
            TradeValueEngine.TradeReputationRegistry.recordDeal(
                teamID: record.initiatorTeamID,
                pointsSent: record.sentValue,
                pointsReceived: record.receivedValue
            )
        case .aiWeeklyOffer:
            TradeValueEngine.TradeReputationRegistry.recordDeal(
                teamID: record.partnerTeamID,
                pointsSent: record.receivedValue,
                pointsReceived: record.sentValue
            )
        case .aiMarket, .aiDeadline, .aiOffseason, .draftDay, .holdoutForced:
            break
        }
    }

    /// Moves one player between teams with NFL cap consequences and returns the
    /// dead cap `from` is left holding.
    ///
    /// The old team drops his full cap hit and picks back up both the
    /// accelerated bonus and the base salary it has already paid out this league
    /// year (task #26); the new team is charged only what is still owed.
    /// `player.annualSalary` is rewritten to that assumed figure so it keeps
    /// matching what the new team is charged — every other engine (contract-year
    /// processing, cuts, valuation) reads `annualSalary` as the cap hit, and
    /// leaving it stale would let cap usage drift on the next expiry.
    private static func movePlayer(
        _ player: Player,
        from oldTeam: Team,
        to newTeam: Team,
        contract: Contract?,
        capMode: CapMode,
        leagueYearRemaining: Double
    ) -> Int {
        let split = CapManagementEngine.tradeCapSplit(
            player: player,
            contract: contract,
            capMode: capMode,
            leagueYearRemaining: leagueYearRemaining
        )

        // **A camp body was never on the seller's ledger** (#205a,
        // `OFFSEASON_ROSTER_PLAN.md` §3.1). The offseason trade market runs in
        // every phase this exemption is live in and the rosters it works are now
        // ten men under the ceiling rather than thirty, so a minimum-salary camp
        // arm going the other way in a package is a real possibility — and the
        // line above would credit `oldTeam` for a salary it was never charged.
        //
        // He joins the buyer as an ordinary man on an ordinary charge: a club
        // that trades FOR somebody has decided he is worth a roster spot, so the
        // camp exemption (which exists for bodies a club is only looking at) has
        // no claim on him. Seller untouched, buyer charged, flag cleared — which
        // also keeps him out of `settleCampBodies`, so the charge lands once.
        if CampRosterEngine.isCampBody(player) {
            CampRosterEngine.clearCampBodyStatus(player)
            newTeam.currentCapUsage += split.salaryAssumed
        } else {
            oldTeam.currentCapUsage =
                max(0, oldTeam.currentCapUsage - player.annualSalary)
                + split.deadCap
                + split.salaryRetained
            newTeam.currentCapUsage += split.salaryAssumed
            // D2: the acceleration the SELLER keeps is remembered, so the March
            // true-up carries it instead of erasing it. Same call the release
            // path makes, for the same reason and with the same two-year shape —
            // one spelling of dead money, not two.
            CapManagementEngine.bookDeadMoney(
                split.deadCap, on: oldTeam,
                contractYearsRemaining: player.contractYearsRemaining
            )
        }

        // Task #45: a midseason deal charges the buyer only the checks still to
        // come, so `annualSalary` drops below the real base. Keep the full number
        // on the row — `FreeAgencyEngine.executeNewLeagueYear` restores it at the
        // rollover, when the discount has actually been earned out. Only a genuine
        // proration is recorded (offseason trades assume the whole year and need
        // no receipt), and an earlier unspent receipt is never overwritten with a
        // second, smaller one: two deadline trades in a row must still restore the
        // salary the player was ORIGINALLY on.
        if split.salaryAssumed < player.annualSalary, player.proratedFullBaseSalary == 0 {
            player.proratedFullBaseSalary = player.annualSalary
        }
        player.annualSalary = split.salaryAssumed
        player.teamID = newTeam.id

        // Cap-compliance wave — the restructure receipt stays with the seller.
        //
        // Paired change for `CapManagementEngine.tradeCapSplit`, which now
        // accelerates restructured money into `split.deadCap`: every unpaid
        // slice of the conversion has just been charged to `oldTeam`, exactly
        // like the signing bonus zeroed on the contract row below and for the
        // same reason — it must not be chargeable twice.
        //
        // The `proratedFullBaseSalary` receipt is written above from the
        // player's CURRENT salary, which still has the restructure proration
        // folded into it. Netting the proration out here is what stops the
        // buyer restoring a second club's conversion at the next rollover and
        // paying for it for the rest of the deal.
        if player.restructureProrationK > 0, player.proratedFullBaseSalary > 0 {
            player.proratedFullBaseSalary =
                max(0, player.proratedFullBaseSalary - player.restructureProrationK)
        }
        player.restructureReliefK = 0
        player.restructureProrationK = 0
        player.restructureCarryYears = 0

        // Contract re-point (finding S3): the row followed nobody before, so the
        // new team's contract screens showed an empty deal and a later cut
        // priced dead money against the wrong franchise. The bonus is zeroed
        // because its remaining proration just accelerated onto `oldTeam` — it
        // must not be chargeable twice.
        if let contract {
            contract.teamID = newTeam.id
            contract.signingBonus = 0
            contract.guaranteedMoney = 0
        }

        return split.deadCap
    }
}
