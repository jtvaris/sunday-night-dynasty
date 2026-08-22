import Foundation
import SwiftData

/// Detects sub-market signed players and orchestrates holdout flow
/// (FA Drama brief, B6).
///
/// Heuristics:
/// - Holdout candidate: actual salary < market value * 0.85.
/// - Resolutions:
///   - `.extend`        : extend contract -> always succeeds (handled elsewhere).
///   - `.signingBonus`  : pay a one-time bonus -> always succeeds.
///   - `.forceTrade`    : capitulate, trade away -> resolves but with PR cost.
///   - `.mediation`     : 75% chance to resolve (random).
@MainActor
enum HoldoutEngine {

    /// Sub-market threshold: salary below 85% of estimated market value triggers holdout candidacy.
    static let subMarketThreshold: Double = 0.85

    /// Mediation success probability (0.0...1.0).
    static let mediationSuccessRate: Double = 0.75

    // MARK: - Losing Costs You Players (D4-C / F-59)

    /// **The term this file did not have.**
    ///
    /// There was no wins term, no morale term and no losing-culture term
    /// anywhere in the holdout model: a star on a 2-15 club applied exactly the
    /// same pressure as the same star on a 15-2 one, and the only way he ever
    /// left was if the user shipped him. `REBUILD_VIABILITY_ANALYSIS.md` §2.6
    /// names it as the missing half of the rebuild's downside — the fast rebuild
    /// currently has **no** cost at all, which is the whole of D4-C.
    ///
    /// `frustration` is the [0, 1] read the walk-out turns on. Two inputs,
    /// because they are the two things a player actually experiences:
    ///
    /// * **the record**, zero at .500 and 1.0 at winless — a man on an 8-9 club
    ///   is not unhappy about the standings;
    /// * **his morale**, zero at ``moraleFloor`` and above — `LockerRoomEngine`
    ///   damps the weekly move to ±3 with a point of reversion to a 70 baseline
    ///   and its own file records that a 4-13 season bleeds only ~−10 over the
    ///   whole year, so morale is a slow, honest signal here rather than a
    ///   second copy of the record.
    ///
    /// Weighted toward the record because the record is the thing the user
    /// controls and the thing the mechanic is supposed to price.
    static func frustration(wins: Int, losses: Int, morale: Int) -> Double {
        let played = max(1, wins + losses)
        let winPct = Double(wins) / Double(played)
        let losingTerm = min(1.0, max(0.0, (0.5 - winPct) * 2.0))
        let moraleTerm = min(1.0, max(0.0, Double(moraleFloor - morale) / Double(moraleFloor)))
        return losingTerm * 0.6 + moraleTerm * 0.4
    }

    /// Morale at or above which a player contributes nothing to `frustration`.
    /// Below the league's 70 baseline: a man at 68 after a bad month is not
    /// asking to be traded.
    static let moraleFloor = 60

    /// Frustration at which a star becomes a holdout candidate on the strength
    /// of the LOSING alone, with nothing wrong with his contract.
    ///
    /// 0.55 needs roughly a 4-13 season with morale already sagging, or a truly
    /// dismal record on its own. That is the "star on a bad team asks out"
    /// story at about the frequency the real league tells it — a handful across
    /// 32 clubs a year, not one per club.
    static let frustratedCandidateThreshold = 0.55

    /// How much a frustrated man's agent multiplies the walk-out roll by, at
    /// full frustration.
    ///
    /// The agent persona still decides who actually walks (hardliner 65 %,
    /// loyalist 30 %, cooperative 15 %) — this scales that draw rather than
    /// replacing it, so the character model stays the thing in charge and
    /// losing is the pressure on it. At `frustration` 1.0 a loyalist's 30 %
    /// becomes 51 %; at 0.0 nothing changes at all, which is what keeps the
    /// average-play line (`REBUILD_VIABILITY_ANALYSIS.md` §3.3, correct today)
    /// where it is: a .500 club sees the identical behaviour it saw before.
    static let frustrationWalkoutScale = 0.7

    /// The chance this player's agent pulls the trigger, given the club's
    /// season. `basePercent` is the persona's own number.
    ///
    /// Lives here and not in the view for the reason every magnitude in this
    /// wave does: a number the UI invents is a number no later audit can find.
    static func walkoutChance(basePercent: Int, frustration: Double) -> Int {
        let scaled = Double(basePercent) * (1.0 + frustration * frustrationWalkoutScale)
        return min(95, max(0, Int(scaled.rounded())))
    }

    /// Holdout resolution path requested by the front office.
    enum Resolution {
        case extend
        case signingBonus
        case forceTrade
        case mediation
    }

    /// Detects players whose contracts are sub-market by 15%+.
    /// - Parameters:
    ///   - roster: The team's current roster.
    ///   - marketValues: Per-player estimated market value (in thousands).
    static func detectHoldoutCandidates(
        roster: [Player],
        marketValues: [UUID: Int]
    ) -> [Player] {
        return roster.filter { player in
            guard let market = marketValues[player.id], market > 0 else { return false }
            // Need at least 1 year remaining; expiring contracts go through normal FA.
            guard player.contractYearsRemaining > 0 else { return false }
            // Salary must be at least sub-market threshold below market.
            return Double(player.annualSalary) < Double(market) * subMarketThreshold
        }
    }

    /// R22: detects STAR players who may hold out at OTAs / start of season.
    ///
    /// A star is OVR >= 85 OR one of the team's top-3 players by overall.
    /// The star holds out when either:
    /// - the contract is expiring (exactly 1 year left), or
    /// - the player is clearly underpaid (salary < 85% of market) with 3+
    ///   years as a pro (players still on rookie deals accept them).
    /// Franchise-tagged players never hold out (the tag binds them) and a
    /// player already holding out is not detected twice.
    ///
    /// D4-C adds a THIRD door alongside the two contract ones: **the club is
    /// losing and he has had enough.** A man on a real deal with real years left
    /// on a 3-14 team asks out, and until now the game had no way for him to.
    /// It is gated on `yearsPro >= 3` like the underpaid door — a rookie on his
    /// first deal has no standing to make demands and does not make them — and
    /// on `contractYearsRemaining > 0`, because a man in his last year simply
    /// leaves in March and does not need a standoff to do it.
    ///
    /// - Parameter teamRecord: the club's season so far. `nil` — every caller
    ///   that existed before D4-C — leaves behaviour byte-for-byte unchanged.
    static func detectStarHoldoutCandidates(
        roster: [Player],
        marketValues: [UUID: Int],
        teamRecord: (wins: Int, losses: Int)? = nil
    ) -> [Player] {
        let topThreeIDs = Set(
            roster.sorted { $0.overall > $1.overall }.prefix(3).map(\.id)
        )
        return roster
            .filter { player in
                guard !player.isFranchiseTagged, !player.isHoldingOut, !player.isInjured else { return false }
                guard let market = marketValues[player.id], market > 0 else { return false }

                let isStar = player.overall >= 85 || topThreeIDs.contains(player.id)
                guard isStar else { return false }

                let expiring = player.contractYearsRemaining == 1
                let underpaid = player.yearsPro >= 3
                    && player.contractYearsRemaining > 0
                    && Double(player.annualSalary) < Double(market) * subMarketThreshold
                let fedUp = teamRecord.map { record in
                    player.yearsPro >= 3
                        && player.contractYearsRemaining > 0
                        && frustration(
                            wins: record.wins,
                            losses: record.losses,
                            morale: player.morale
                        ) >= frustratedCandidateThreshold
                } ?? false
                return expiring || underpaid || fedUp
            }
            // Biggest pay gap first — the angriest star leads the drama.
            .sorted {
                let gapA = (marketValues[$0.id] ?? 0) - $0.annualSalary
                let gapB = (marketValues[$1.id] ?? 0) - $1.annualSalary
                return gapA > gapB
            }
    }

    /// Initiates a holdout for a player. Returns the persisted Holdout record,
    /// or `nil` if a save error occurs. R22: flags the player as holding out
    /// so simulation, development and UI all see the same state.
    /// - Parameter seasonYear: `career.currentSeason` at the time the standoff
    ///   begins. Stamped on the record so the phase-2 camp pipeline can tell a
    ///   holdout settled THIS offseason (health gate 0.7 — he missed camp) from
    ///   one settled years ago. `0` leaves it unknown.
    static func startHoldout(
        player: Player,
        teamID: UUID,
        subMarketDelta: Int,
        seasonYear: Int = 0,
        modelContext: ModelContext
    ) -> Holdout? {
        let holdout = Holdout(
            playerID: player.id,
            teamID: teamID,
            subMarketDelta: subMarketDelta
        )
        holdout.seasonYear = seasonYear
        holdout.careerID = player.careerID
        player.isHoldingOut = true
        modelContext.insert(holdout)
        do {
            try modelContext.save()
            return holdout
        } catch {
            player.isHoldingOut = false
            return nil
        }
    }

    /// Resolves a holdout and persists the outcome. Returns `true` on success.
    /// R22: pass the player so a successful resolution clears `isHoldingOut`.
    ///
    /// Wave 1: `.forceTrade` now really ships the player out (see `forceTrade`)
    /// instead of stamping `.traded` on a player who stayed on the roster
    /// (`docs/TRADE_OVERHAUL_PLAN.md` finding S3). When no partner will pay a
    /// fair price the resolution still succeeds and the player reports back —
    /// the old behaviour, kept as the honest fallback.
    /// - Parameter onForcedTrade: called with the trade result when the
    ///   `.forceTrade` path runs, so a UI can name the partner and the return
    ///   (or say "no market"). Optional so existing call sites are unchanged.
    @discardableResult
    static func resolveHoldout(
        holdout: Holdout,
        resolution: Resolution,
        player: Player? = nil,
        modelContext: ModelContext,
        onForcedTrade: ((ForcedTradeOutcome) -> Void)? = nil
    ) -> Bool {
        let success: Bool
        let mappedResolution: HoldoutResolution

        switch resolution {
        case .extend:
            success = true
            mappedResolution = .extended
        case .signingBonus:
            success = true
            mappedResolution = .bonusGiven
        case .forceTrade:
            success = true
            mappedResolution = .traded
            if let player {
                let outcome = forceTrade(
                    player: player,
                    holdout: holdout,
                    modelContext: modelContext
                )
                onForcedTrade?(outcome)
            }
        case .mediation:
            success = Double.random(in: 0...1) < mediationSuccessRate
            mappedResolution = success ? .extended : .unresolved
        }

        if success {
            holdout.resolvedAt = Date()
            holdout.resolution = mappedResolution
            player?.isHoldingOut = false
        } else {
            holdout.resolution = .unresolved
        }

        try? modelContext.save()
        return success
    }

    // MARK: - Forced Trade (Wave 1 — `docs/TRADE_OVERHAUL_PLAN.md`, finding S3)

    /// What the front office managed to get for a holding-out player.
    enum ForcedTradeOutcome {
        /// He is gone: `partnerAbbr` acquired him for `returnDescription`.
        case traded(partnerAbbr: String, returnDescription: String)
        /// Nobody would pay a fair price, so he stays and reports back. This is
        /// the pre-Wave-1 behaviour, kept as the honest fallback rather than
        /// forcing a bad deal through.
        case noMarket
    }

    /// Actually ships a holding-out player out of town.
    ///
    /// `.forceTrade` used to be a lie: it stamped the holdout `.traded` and left
    /// the player on the roster (finding S3). This builds a real fair-value
    /// package through `TradeValueEngine` — the game's one valuation authority —
    /// and executes it through `TradeEngine.executeTrade`, so the deal moves the
    /// player, re-points his contract, charges dead money to the team that
    /// caved, and writes a `TradeRecord` row like every other trade.
    ///
    /// League state (season/week/phase/cap mode) is read from the `Career` that
    /// owns the holdout's team instead of being passed in: this is called from
    /// the holdout dialog's resolve closure, which has no reason to know about
    /// trade plumbing.
    ///
    /// Defensive by design — any missing piece (no career, trade window shut,
    /// no partner, no believable package) returns `.noMarket` and mutates
    /// nothing.
    @discardableResult
    static func forceTrade(
        player: Player,
        holdout: Holdout,
        modelContext: ModelContext
    ) -> ForcedTradeOutcome {
        // The old `?? careers.first` fallback silently ran a forced trade
        // against ANOTHER save's cap mode, season and news log. The holdout row
        // now names its own save, so the lookup is exact or it bails.
        let careers = (try? modelContext.fetch(FetchDescriptor<Career>())) ?? []
        guard let career = careers.first(where: { $0.id == holdout.careerID })
                ?? careers.first(where: { $0.id == player.careerID })
        else { return .noMarket }
        let cid = career.id

        // Holdouts break out at OTAs, where the window is open — but never
        // assume it: the same dialog can be reached mid-season.
        guard TradeValueEngine.isTradeWindowOpen(
            phase: career.currentPhase,
            week: career.currentWeek
        ) else { return .noMarket }

        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        guard let sellingTeam = allTeams.first(where: { $0.id == holdout.teamID }) else { return .noMarket }

        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let allPicks = ((try? modelContext.fetch(FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? [])
            .filter { !$0.isComplete }
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        guard let package = TradeValueEngine.buildForcedTradePackage(
            player: player,
            sellingTeam: sellingTeam,
            allTeams: allTeams,
            allPlayers: allPlayers,
            allPicks: allPicks,
            contracts: contracts,
            capMode: career.capMode,
            currentSeason: career.currentSeason
        ) else {
            // No market: leave the roster exactly as it was.
            return .noMarket
        }

        let outcome = TradeEngine.executeTrade(
            proposal: package.proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            capMode: career.capMode,
            ledger: TradeLedger.Context(
                kind: .holdoutForced,
                season: career.currentSeason,
                week: career.currentWeek,
                phase: career.currentPhase
            ),
            modelContext: modelContext
        )

        // A forced trade is league news like any other executed deal — the
        // user gave up a star; the whole league heard about it.
        if let record = outcome.record {
            let teams = (try? modelContext.fetch(FetchDescriptor<Team>(
                predicate: #Predicate { $0.careerID == cid }
            ))) ?? []
            let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
            let announcement = TradeNewsFactory.announce(
                record: record, teamsByID: teamsByID, userTeamID: career.teamID
            )
            // F-49(1): this was `newsLog.append`, which on a career already
            // holding 150 items encoded the headline straight into the bin.
            career.postNews(announcement.news)
            // F-49(2): and the receipt was dropped on the floor. The user gave
            // up his own star and got no inbox message naming what came back.
            // `lastInboxMessages` is the channel a flow running with the shell
            // off screen stages mail on; the shell drains it on the next
            // navigation change, which is the dialog closing.
            if let receipt = announcement.inbox {
                WeekAdvancer.lastInboxMessages.append(receipt)
            }
        }

        // He left angry, but he left: the standoff is over either way.
        player.isHoldingOut = false
        try? modelContext.save()

        return .traded(
            partnerAbbr: package.partner.abbreviation,
            returnDescription: package.returnDescription
        )
    }
}
