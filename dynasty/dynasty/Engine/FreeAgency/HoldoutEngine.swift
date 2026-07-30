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
    static func detectStarHoldoutCandidates(
        roster: [Player],
        marketValues: [UUID: Int]
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
                return expiring || underpaid
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
        let careers = (try? modelContext.fetch(FetchDescriptor<Career>())) ?? []
        guard let career = careers.first(where: { $0.teamID == holdout.teamID }) ?? careers.first
        else { return .noMarket }

        // Holdouts break out at OTAs, where the window is open — but never
        // assume it: the same dialog can be reached mid-season.
        guard TradeValueEngine.isTradeWindowOpen(
            phase: career.currentPhase,
            week: career.currentWeek
        ) else { return .noMarket }

        let allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        guard let sellingTeam = allTeams.first(where: { $0.id == holdout.teamID }) else { return .noMarket }

        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        let allPicks = ((try? modelContext.fetch(FetchDescriptor<DraftPick>())) ?? [])
            .filter { !$0.isComplete }
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>())) ?? []

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

        TradeEngine.executeTrade(
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

        // He left angry, but he left: the standoff is over either way.
        player.isHoldingOut = false
        try? modelContext.save()

        return .traded(
            partnerAbbr: package.partner.abbreviation,
            returnDescription: package.returnDescription
        )
    }
}
