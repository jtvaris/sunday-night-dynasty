import Foundation
import SwiftData

// MARK: - Cap Management Engine

/// Handles advanced salary cap operations: rollover, compensatory picks,
/// contract year processing, and annual cap growth.
enum CapManagementEngine {

    // MARK: - Cap Rollover

    /// Calculates how much unused cap space rolls over into the next season.
    /// Per NFL rules, up to 20% of the total salary cap can carry forward.
    ///
    /// - Parameters:
    ///   - team: The team whose cap space is being evaluated.
    ///   - season: The season year (used for logging/display purposes).
    /// - Returns: The rollover amount in thousands of dollars.
    static func calculateCapRollover(team: Team, season: Int) -> Int {
        let unusedCap = team.salaryCap - team.currentCapUsage
        guard unusedCap > 0 else { return 0 }

        // NFL cap rollover is capped at 20% of the current year's cap
        let maxRollover = Int(Double(team.salaryCap) * 0.20)
        return min(unusedCap, maxRollover)
    }

    /// Cap-mode-aware rollover. Sandbox returns 0 since the cap is not enforced.
    static func calculateCapRollover(team: Team, season: Int, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return calculateCapRollover(team: team, season: season)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Compensatory Picks

    /// Awards compensatory draft picks to teams that lost more valuable free agents
    /// than they signed. Picks are in rounds 3 through 7, based on the value delta
    /// between departed and acquired free agents.
    ///
    /// - Parameters:
    ///   - team: The team receiving comp pick consideration.
    ///   - lostFreeAgents: Players who left this team in free agency.
    ///   - gainedFreeAgents: Players this team signed in free agency.
    /// - Returns: An array of compensatory `DraftPick` objects, empty if no comp picks awarded.
    static func processCompensatoryPicks(
        team: Team,
        lostFreeAgents: [Player],
        gainedFreeAgents: [Player]
    ) -> [DraftPick] {

        let salaryCap = team.salaryCap
        let lostValue = lostFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: salaryCap) }
        let gainedValue = gainedFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: salaryCap) }

        let valueDelta = lostValue - gainedValue
        guard valueDelta > 0 else { return [] }

        // Number of comp picks scales with how much value was lost
        // Each threshold of $5M in lost value earns one pick (max 4 picks per season)
        let numPicks = min(valueDelta / 5_000, 4)
        guard numPicks > 0 else { return [] }

        var picks: [DraftPick] = []

        for i in 0..<numPicks {
            // First comp pick is a 3rd-round caliber pick; subsequent picks step down in round
            // Rounds 3, 4, 5, 6, 7 — capped at round 7
            let round = min(3 + i, 7)
            let pick = DraftPick(
                seasonYear: 0, // Caller should set the correct season year
                round: round,
                pickNumber: 33 + (i * 10), // Estimated late pick number within the round
                originalTeamID: team.id,
                currentTeamID: team.id
            )
            picks.append(pick)
        }

        return picks
    }

    // MARK: - Contract Year Processing
    //
    // DELETED (task #94): `processContractYear(players:team:)`.
    //
    // A third, never-called implementation of the contract clock — it decremented
    // `contractYearsRemaining`, released expiries and refunded the cap, i.e. it
    // did the whole job of `FreeAgencyEngine.executeNewLeagueYear` in fifteen
    // lines with none of its guards. It had zero call sites for its entire life
    // and survived the single-clock rewrite (`Career.lastRolloverSeason`, which
    // killed the duplicate week-18 tick), where it was a live landmine: anything
    // that wired it up would have advanced every contract a second time inside
    // one league year and silently emptied rosters.

    /// Calculates dead cap charge when a player is cut mid-contract.
    /// Dead cap = remaining prorated signing bonus + any guaranteed base salaries.
    ///
    /// - Parameters:
    ///   - contract: The player's detailed contract.
    ///   - team: The team cutting the player.
    /// - Returns: Dead cap charge in thousands of dollars for the current year.
    static func calculateDeadCap(for contract: Contract, team: Team) -> Int {
        // Delegate to the Contract model's own deadCap computed property
        return contract.deadCap
    }

    /// Cap-mode-aware dead cap. Sandbox always returns 0 — releases are free.
    static func calculateDeadCap(for contract: Contract, team: Team, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return calculateDeadCap(for: contract, team: team)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Trade Cap Split (Wave 1 — `docs/TRADE_OVERHAUL_PLAN.md`, finding S3)

    /// How one traded player's money divides between the two teams.
    ///
    /// Trades used to be free salary dumps: `TradeEngine.executeTrade` moved
    /// `annualSalary` 1:1, so a team could hand a bloated contract to the AI
    /// and pocket every dollar (plan finding S3). Real NFL rules — and the
    /// game's own cut path — say the signing-bonus proration cannot follow the
    /// player: it accelerates onto the team that paid it.
    struct TradeCapSplit {
        /// Signing-bonus acceleration the TRADING team keeps on its books,
        /// in thousands. Identical model to a release (`calculateDeadCap`).
        let deadCap: Int
        /// Cap hit the ACQUIRING team takes on, in thousands: the share of the
        /// player's base salary that is still UNPAID at the moment of the trade
        /// (see `leagueYearRemaining` — the whole base for an offseason deal,
        /// ~55 % of it at a Week 9 deadline).
        let salaryAssumed: Int
        /// This year's prorated bonus slice — the part that stays behind.
        let proratedPerYear: Int
        /// Base salary the TRADING team has already paid out this league year
        /// and therefore keeps on its own books, in thousands. Zero for any
        /// trade struck outside the regular season.
        let salaryRetained: Int

        /// Cap space the trading team actually frees up (can be negative when
        /// the acceleration is larger than the salary relief — a real and
        /// deliberately painful outcome for bonus-heavy deals).
        var traderRelief: Int { salaryAssumed + proratedPerYear - deadCap - salaryRetained }
    }

    // MARK: - League-year proration (task #26)

    /// Regular-season weeks in one league year.
    ///
    /// Local to the cap model on purpose: what proration needs is the LENGTH of
    /// the paid season, not the schedule (`ScheduleGenerator`'s copy is private
    /// to the scheduler and describes when games are played, not when money is
    /// earned). The two are the same number today and would stay in step by
    /// definition if the season were ever lengthened.
    static let regularSeasonWeeks = 18

    /// The share of the league year still ahead at `week` of `phase`, 0…1.
    ///
    /// NFL base salary is earned week by week: a club that acquires a player at
    /// the deadline is charged only the game checks he has left to collect, and
    /// the club that traded him keeps what it already paid. `tradeCapSplit`
    /// multiplies the base by this fraction, which is why a deadline rental is
    /// affordable to a team that could never carry the same contract in March.
    ///
    /// Bounds worth knowing: the trade window closes after
    /// `TradeValueEngine.deadlineWeek` (9 of 18), so an in-season trade can
    /// never carry a fraction below 10/18 ≈ 0.56 — the model is a discount of at
    /// most ~44 %, never a rounding-to-nothing. Every offseason phase returns
    /// 1.0: a March acquisition owes the whole season.
    ///
    /// PAIRED CHANGE STILL OPEN (handoff to the `TradeValueEngine` owner):
    /// `capDeltas` — and through it `validationErrors`, `canAbsorbExactly` and
    /// the Trade Center's cap preview — still calls `tradeCapSplit` without a
    /// fraction, i.e. it prices a deadline deal at full-season cost while
    /// execution now charges the prorated one. The divergence is in the SAFE
    /// direction (the preview is stricter than the outcome, so no illegal deal
    /// can slip through) but it is a divergence: pass
    /// `leagueYearRemaining(phase:week:)` there and the plan's 5 % AI market cap
    /// slack (`aiMarketCapSlackFraction`) can shrink or go away entirely.
    static func leagueYearRemaining(phase: SeasonPhase, week: Int) -> Double {
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs:
            let weeksLeft = regularSeasonWeeks - max(1, week) + 1
            let fraction = Double(weeksLeft) / Double(regularSeasonWeeks)
            return min(1.0, max(1.0 / Double(regularSeasonWeeks), fraction))
        default:
            return 1.0
        }
    }

    /// Splits a traded player's money the same way a release does.
    ///
    /// The dead-cap figure is exactly the cut path's: `Contract.deadCap`
    /// (remaining prorated bonus for every year still on the deal) when a
    /// detailed contract row exists, and `RosterCutEvaluator.deadCap` — the
    /// 15 %-of-salary-per-year proxy — when it does not. Most players have no
    /// `Contract` row (they are only minted for realistic-mode FA signings),
    /// so the proxy is the common path and must agree with what the cut screens
    /// already quote.
    ///
    /// The base salary the receiver assumes is derived from `player.annualSalary`
    /// rather than `Contract.baseSalary`, because `annualSalary` is the unit the
    /// rest of the game charges against `Team.currentCapUsage`; deriving the
    /// split from it keeps one cap unit and stops the two ledgers drifting.
    ///
    /// Sandbox keeps the old 1:1 behaviour: cap rules are off, so there is no
    /// dead money to eat and the receiver takes the full salary.
    ///
    /// ## Midseason proration (task #26)
    ///
    /// `leagueYearRemaining` is the share of the season still unpaid — 1.0
    /// everywhere except the regular season, where it is
    /// `leagueYearRemaining(phase:week:)`. The base salary splits on it:
    ///
    /// ```
    /// base            = annualSalary − proratedPerYear   (the bonus stays behind)
    /// salaryAssumed   = base × leagueYearRemaining       (buyer: the checks still to come)
    /// salaryRetained  = base − salaryAssumed             (seller: the checks already written)
    /// ```
    ///
    /// The two halves always sum back to `base`, so a trade moves cap charge
    /// between two clubs and never creates or destroys any. The model is the
    /// same shape as the dead-money math directly above it: money already spent
    /// stays with the club that spent it, money still owed follows the player.
    ///
    /// WHY it matters beyond realism: with the full-season charge, a deadline
    /// buyer had to fit twelve months of salary under a cap he had already spent
    /// ten months of — which is why the league market needed
    /// `TradeValueEngine.aiMarketCapSlackFraction` to function at all (1240 of
    /// 1530 candidate deals that had cleared both GMs' VALUE bars died on the
    /// cap check). At the Week 9 deadline the charge is now 10/18 of the base.
    ///
    /// `TradeEngine` writes `salaryAssumed` back into `player.annualSalary`
    /// (the cap ledger and the salary must agree within a league year), and
    /// records the full base in `Player.proratedFullBaseSalary` so
    /// `FreeAgencyEngine.executeNewLeagueYear` restores it at the rollover —
    /// a deadline acquisition is booked at his real number from the next
    /// league year on (task #45).
    static func tradeCapSplit(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> TradeCapSplit {
        let salary = max(0, player.annualSalary)

        guard capMode != .sandbox else {
            return TradeCapSplit(
                deadCap: 0,
                salaryAssumed: salary,
                proratedPerYear: 0,
                salaryRetained: 0
            )
        }

        // Remaining years drive the acceleration, same as a mid-contract cut.
        let years: Int
        let rawDead: Int
        if let contract, contract.totalYears > 0 {
            years = max(1, contract.totalYears - contract.currentYear)
            // Exactly what `calculateDeadCap(for:team:)` returns for a release.
            rawDead = contract.deadCap
        } else {
            years = max(1, player.contractYearsRemaining)
            rawDead = RosterCutEvaluator.deadCap(player: player)
        }

        // Never let the accelerated bonus exceed the money actually left on the
        // deal — a runaway charge would make the AI market unsolvable.
        let clampedDead = max(0, min(rawDead, salary * years))

        // Restructured money accelerates too (cap-compliance wave, task #68).
        //
        // A restructure converted base salary into signing bonus and spread it
        // across the years still on the deal; every unpaid slice of it comes due
        // the moment the man leaves. Without this the lever would be free — take
        // the relief in March, cut him in August, never pay the proration — which
        // is exactly the "restructure is a cheat code" failure the real cap
        // prevents. Added OUTSIDE the clamp above on purpose: that clamp bounds
        // the ORIGINAL deal's bonus against the salary still owed on it, and the
        // restructure charge is separately bounded by construction (`p × N` can
        // never exceed the base that was converted, which was itself capped at
        // this year's base salary less the veteran minimum).
        //
        // Sandbox never books the relief, so it must never book the charge; the
        // early return above has already covered it.
        let deadCap = clampedDead + max(0, player.restructureDeadMoney)
        let proratedPerYear = deadCap / years

        let base = max(0, salary - proratedPerYear)
        let remaining = min(1.0, max(0.0, leagueYearRemaining))
        let assumed = Int((Double(base) * remaining).rounded())

        return TradeCapSplit(
            deadCap: deadCap,
            salaryAssumed: assumed,
            proratedPerYear: proratedPerYear,
            salaryRetained: base - assumed
        )
    }

    // MARK: - Release Cap Split (task #68)

    /// How one released player's money divides between relief and dead charge.
    ///
    /// A release is the same transaction as a trade with nobody on the other
    /// side: the signing-bonus proration accelerates onto the club that paid it,
    /// and the base salary still owed simply stops being owed. `releaseCapSplit`
    /// is therefore derived from `tradeCapSplit` rather than modelled twice —
    /// what the buyer would have ASSUMED is exactly what the seller RELIEVES.
    ///
    /// Before this existed there were four different answers to "what does
    /// cutting this man cost": `RosterCutEvaluator.deadCap` (15 %/yr, used by the
    /// trade path), `RosterCutView` (a flat 20 % of salary), `PlayerContractView`
    /// (50 % for display, ZERO when the button was actually pressed) and
    /// `PlayerDetailView` (salary × years ÷ 4). Only one of them ever reached
    /// `Team.currentCapUsage`, and it booked no dead money at all.
    struct ReleaseCapSplit {
        /// Signing-bonus acceleration that stays on the club's books, in
        /// thousands. Identical model to `TradeCapSplit.deadCap`.
        let deadCap: Int
        /// Base salary the club stops owing, in thousands: the share of the base
        /// still UNPAID at the moment of the release (see `leagueYearRemaining`).
        let salaryRelieved: Int
        /// Base salary already paid out this league year. Stays charged — money
        /// spent does not come back because the man left.
        let salaryRetained: Int
        /// This year's prorated bonus slice, i.e. the part of the cap hit that was
        /// bonus rather than salary.
        let proratedPerYear: Int
        /// Set when the release door REFUSED the move (#208 G1): nothing was
        /// written, no money moved, and this sentence is the reason to put in
        /// front of the user. `nil` on every release that actually happened.
        ///
        /// A refusal is deliberately a value rather than a thrown error: every
        /// caller of ``applyRelease`` already treats the split as the receipt
        /// for what happened, and the ones that discard it get the safe
        /// outcome (nothing at all) instead of a crash or a half-applied
        /// release.
        var refusalReason: String? = nil

        /// The door said no — see ``refusalReason``.
        var isRefused: Bool { refusalReason != nil }

        /// A refusal: every column zero, because nothing was booked.
        static func refused(_ reason: String) -> ReleaseCapSplit {
            ReleaseCapSplit(
                deadCap: 0,
                salaryRelieved: 0,
                salaryRetained: 0,
                proratedPerYear: 0,
                refusalReason: reason
            )
        }

        /// Cap space the release actually frees, in thousands. Negative when the
        /// acceleration outruns the salary relief — a bonus-heavy contract can
        /// cost MORE to cut than to keep, which is the whole point of dead money.
        ///
        /// ## Why `proratedPerYear` is NOT scaled by `leagueYearRemaining`
        ///
        /// Read term by term this looks asymmetric — base is prorated by the
        /// weeks left, the bonus slice is not — and reads as though a Week 12
        /// release relieved a whole league year of bonus money. It does not, and
        /// the reason is that `deadCap` charges the same slice straight back:
        /// `deadCap` is the acceleration for EVERY remaining year *including the
        /// current one* (`Contract.deadCap` / `RosterCutEvaluator.deadCap`), and
        /// `proratedPerYear = deadCap / years`. So
        ///
        ///     capSavings = salaryRelieved + proratedPerYear − deadCap
        ///                = salaryRelieved − (bonus for the years AFTER this one)
        ///
        /// and this year's proration nets to zero: removed from the cap hit,
        /// re-added inside the residual. Worked example — 10 000K / 3 yrs, cut in
        /// Week 12 (`leagueYearRemaining` = 7/18): deadCap 4 500, proratedPerYear
        /// 1 500, base 8 500, relieved 3 306, retained 5 194 → capSavings **306**
        /// = 3 306 unpaid base − 3 000 accelerated future bonus, residual 9 694.
        /// The club keeps every cent it has already spent plus the whole
        /// acceleration, which is the correct pre-June-1 answer.
        var capSavings: Int { salaryRelieved + proratedPerYear - deadCap }

        /// What the club is still charged for this player after the release.
        var residualCharge: Int { salaryRetained + deadCap }
    }

    /// Prices a release without applying it — for previews and confirmations.
    ///
    /// `leagueYearRemaining` follows the same in-season rules as a trade (#26 /
    /// #44 / #45): a Week 12 release only relieves the game checks still to come,
    /// and every offseason phase relieves the whole base.
    ///
    /// **A camp cut is priced at zero, in both columns** (#205a,
    /// `OFFSEASON_ROSTER_PLAN.md` §3.1). A camp body's minimum salary is
    /// deliberately never added to `Team.currentCapUsage`, so releasing him
    /// frees nothing and costs nothing — and that has to be the answer HERE, in
    /// the shared pricing function, not only inside ``applyRelease``. Four
    /// screens preview a release through this call (the cut ladder, the player
    /// detail cut, the contract screen and the cap-compliance lever list); if it
    /// answered `750` while the ledger moved `0`, the cut sheet would promise
    /// savings that never arrive, and — worse — `complianceLevers` would offer
    /// "release these camp bodies" as a way out of a cap violation it cannot fix.
    static func releaseCapSplit(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> ReleaseCapSplit {
        guard !CampRosterEngine.isCampBody(player) else {
            return ReleaseCapSplit(
                deadCap: 0, salaryRelieved: 0, salaryRetained: 0, proratedPerYear: 0
            )
        }
        let split = tradeCapSplit(
            player: player,
            contract: contract,
            capMode: capMode,
            leagueYearRemaining: leagueYearRemaining
        )
        return ReleaseCapSplit(
            deadCap: split.deadCap,
            salaryRelieved: split.salaryAssumed,
            salaryRetained: split.salaryRetained,
            proratedPerYear: split.proratedPerYear
        )
    }

    // MARK: - Positional integrity (#208 G1)
    //
    // The cut sheet learned this rule first (#208a, `RosterCutEvaluator`), and
    // it held — on the cut sheet. QA then released all three quarterbacks one
    // at a time from the PLAYER DETAIL screen, walked into the preseason with
    // an empty QB room and a formation reading "EMPTY 0/1", because the guard
    // lived in one view instead of behind the door every release goes through.
    //
    // So the rule moves here, to the one release authority, in two halves:
    //
    //   * ``releaseBlockReason`` — the sentence a screen shows and disables its
    //     button with, BEFORE the user commits to anything.
    //   * ``applyRelease`` — the same call, run again at the door, which
    //     refuses the write when it comes back non-nil.
    //
    // Neither half owns the floors: both read `RosterCutEvaluator.minimumCount`,
    // which reads `TradeValueEngine.starterSlots`. One table, three rules (the
    // trade validator's positional integrity, the cut sheet, this door).

    /// Who is asking for the release, and against which roster the positional
    /// floors are measured.
    ///
    /// The default is the ENFORCING case, on purpose: a release path added
    /// later is guarded before anyone remembers to guard it, and opting out
    /// costs a visible `.leagueSweep` at the call site.
    enum ReleaseAuthority {
        /// A club decision, checked against the roster the caller already has
        /// in hand. Cheapest and the one the four user screens use — they are
        /// all rendering that roster anyway.
        case club(roster: [Player])

        /// A club decision whose roster the door fetches from the store itself.
        /// The default. Needs a `modelContext`; without one there is no room to
        /// count and the door cannot invent one, so it lets the release through
        /// — which is exactly why the engine paths below name their case out
        /// loud rather than leaning on this fallback.
        case clubResolvingRoster

        /// League churn: the AI cutdown and the practice-squad corresponding
        /// move. These paths filter their OWN candidate lists through
        /// ``releaseBlockReason`` before they get here (`WeekAdvancer.trimAIRosters`,
        /// `PracticeSquadEngine.signToActiveRoster`), so the door must not
        /// second-guess them — a sweep that stalls on a refusal would leave 31
        /// clubs sitting over the 53-man ceiling for the rest of the save.
        case leagueSweep
    }

    /// Why this club cannot release this man, or `nil` when the move is legal.
    ///
    /// **The one validator.** Every screen with a Release button asks this
    /// before it enables the button, and ``applyRelease`` asks it again before
    /// it writes — so a stale tap, a deep link or a roster that moved between
    /// render and commit all land on the same answer.
    ///
    /// - Parameter roster: any array the club's men can be found in — a live
    ///   `@Query`, a fetched club roster, the cut sheet's snapshot. It is
    ///   filtered to the club's CURRENT, non-retired members here, which is
    ///   what makes a sequence of releases safe: a man released a moment ago
    ///   has `teamID == nil` and has already left the room being counted.
    /// - Parameter alreadySelected: men the user has ticked on a cut sheet but
    ///   not yet released. Rooms close one man at a time as the sheet fills.
    static func releaseBlockReason(
        player: Player,
        team: Team,
        roster: [Player],
        alreadySelected: Set<UUID> = []
    ) -> String? {
        let teamID = team.id
        let room = roster.filter { $0.teamID == teamID && !$0.isRetired }
        // Not on this club's books (already cut, retired, traded): releasing him
        // again is a no-op that empties nothing, and answering "last QB" here
        // would block the re-tap for a reason that is not true.
        guard room.contains(where: { $0.id == player.id }) else { return nil }
        return RosterCutEvaluator.releaseBlockReason(
            player: player,
            roster: room,
            alreadySelected: alreadySelected
        )
    }

    /// The door's own check — resolves the roster the authority describes, then
    /// asks the validator above.
    private static func releaseRefusal(
        player: Player,
        team: Team,
        authority: ReleaseAuthority,
        modelContext: ModelContext?
    ) -> String? {
        let roster: [Player]
        switch authority {
        case .leagueSweep:
            return nil
        case .club(let supplied):
            roster = supplied
        case .clubResolvingRoster:
            guard let modelContext else { return nil }
            let teamID = team.id
            let descriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.teamID == teamID }
            )
            guard let fetched = try? modelContext.fetch(descriptor) else { return nil }
            roster = fetched
        }
        return releaseBlockReason(player: player, team: team, roster: roster)
    }

    /// Releases a player and books the release on the club's cap ledger.
    ///
    /// The ONE place a release is applied. It mirrors `WeekAdvancer.trimAIRosters`
    /// (the AI cutdown) field for field so a user release and an AI release leave
    /// the store in the same shape, and it books the dead-cap charge that the two
    /// user-facing cut screens never booked at all.
    ///
    /// The ledger identity `CapOverviewView` derives its Dead Money card from —
    /// `dead = currentCapUsage − Σ roster cap hits` — holds because the player
    /// leaves the roster in the same call that adjusts the total: usage drops by
    /// `capSavings`, the roster loses a cap hit of `salaryRelieved +
    /// salaryRetained + proratedPerYear`, and the difference left behind is
    /// exactly `residualCharge`.
    ///
    /// **That identity is EXACT only where the screen and this call price the
    /// same cap hit.** The split is derived from `player.annualSalary` (the unit
    /// `Team.currentCapUsage` is charged in, see `tradeCapSplit`), while
    /// `CapOverviewView.capHit(for:)` prefers `Contract.capHit` when a detailed
    /// row exists. For a player with no `Contract` — the common case, since rows
    /// are only minted for realistic-mode signings — the two agree and the
    /// residual is exactly `residualCharge`. For a player WITH one they differ
    /// by `contract.capHit − annualSalary`, and the release moves the ledger by
    /// that much less (or more) than the card's arithmetic expects. That gap is
    /// pre-existing and the screen already surfaces it as "Ledger variance", but
    /// this task newly routes realistic-mode `Contract` players down this path,
    /// so it is stated here rather than left to be rediscovered. Closing it is
    /// task #87's single-salary-source work, not this call's.
    ///
    /// **Scope note:** the dead-money ledger is rebuilt from rostered salaries at
    /// every league-year rollover (`FreeAgencyEngine`'s task-#27 true-up), so a
    /// residual booked here is a WITHIN-league-year figure by design. It does not
    /// survive March, and the Dead Money card is not a multi-year obligation.
    ///
    /// Sandbox never charged the cap on signing, so it must not credit it on
    /// release either — the player simply leaves.
    ///
    /// - Parameter modelContext: When supplied, every `Contract` row belonging to
    ///   this player is deleted as part of the release. The rows are keyed by
    ///   `teamID`, and `RosterCutView.loadContracts` / `CapComplianceView.loadData`
    ///   fetch on exactly that key, so a row left attached would keep a released
    ///   man in the club's contract map forever — harmless while every consumer
    ///   keys off `Player.teamID`, a live double-count the moment anything sums
    ///   contracts by team. Callers with no context (the AI cutdown path) pass
    ///   nil; those players have no `Contract` row to begin with.
    /// - Parameter careerID: the save whose forward ledger the released man's
    ///   franchise tag is dropped from. `career.id`, matching every reader of
    ///   that table; omitting it falls back to `Player.careerID`, which is
    ///   optional and releases nothing when nil.
    /// - Parameter reason: what the receipt says happened (#188). Only reaches
    ///   storage on the paths that pass a `modelContext`.
    /// - Parameter seasonYear: the league year the receipt is filed under.
    ///   Omitted, it is read off the `Career` the resolved `careerID` names —
    ///   which is why a caller with a context but no career in reach still
    ///   books nothing rather than filing the cut under year zero.
    /// - Parameter authority: who is asking, and what roster the positional
    ///   floors are checked against (#208 G1). Defaults to the enforcing case;
    ///   a refused release writes NOTHING and comes back as
    ///   ``ReleaseCapSplit/refused(_:)``.
    @discardableResult
    static func applyRelease(
        player: Player,
        team: Team,
        authority: ReleaseAuthority = .clubResolvingRoster,
        contract: Contract? = nil,
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0,
        careerID: UUID? = nil,
        reason: ReleaseReason = .rosterMove,
        seasonYear: Int? = nil,
        modelContext: ModelContext? = nil
    ) -> ReleaseCapSplit {
        // **The positional floor, at the door** (#208 G1). Checked BEFORE a
        // single field is written, because everything below this line is
        // irreversible: the man's teamID, his salary, his contract rows and the
        // club's ledger all move in one pass with no rollback.
        //
        // Every user-facing screen disables its Release button on the same
        // sentence, so reaching this refusal means the roster moved between the
        // render and the tap — which is precisely the case a view-side guard
        // cannot cover, and the case QA walked through three times in a row.
        if let refusal = releaseRefusal(
            player: player,
            team: team,
            authority: authority,
            modelContext: modelContext
        ) {
            return .refused(refusal)
        }

        // **A camp body was never charged** (#205a, `OFFSEASON_ROSTER_PLAN.md`
        // §3.1). His minimum salary is written on his row but deliberately kept
        // off `Team.currentCapUsage` for the four offseason phases he is carried
        // — that exemption is how a 64-man club can carry 80 men through camp
        // without the compliance window hard-gating all 32 of them.
        //
        // The exemption only holds if the refund path knows about it, and this
        // is the one release door (#102 F8) every camp cut walks through. A
        // credit here would walk the club's ledger down by his full salary on
        // every one of the ~27 releases a cutdown makes — ~$12M a club, a camp,
        // and it compounds every season. ``releaseCapSplit`` prices him at zero
        // in both columns (no relief, and no dead money either — booking
        // `0.15 × salary` against a charge that was never made would be the same
        // leak with the sign flipped), so the line below moves nothing and the
        // receipt says a camp cut cost nothing, which is the truth.
        //
        // `clearCampBodyStatus` is load-bearing, not tidiness: a man who kept
        // the flag after his release would be exempted from the credit on his
        // NEXT, fully charged release, and the club's usage would ratchet up by
        // his salary every time.
        let split = releaseCapSplit(
            player: player,
            contract: contract,
            capMode: capMode,
            leagueYearRemaining: leagueYearRemaining
        )
        CampRosterEngine.clearCampBodyStatus(player)

        if capMode != .sandbox {
            // `capSavings` is signed: a negative value (acceleration larger than
            // the relief) correctly RAISES the club's usage.
            team.currentCapUsage = max(0, team.currentCapUsage - split.capSavings)
        }

        player.teamID = nil
        player.annualSalary = 0
        player.contractYearsRemaining = 0
        player.proratedFullBaseSalary = 0
        // The restructure receipt is spent: its acceleration was just charged
        // into `split.deadCap` above and booked against the club that paid it.
        // Leaving it on the row would follow the man to his next employer and
        // charge a second club for a bonus it never wrote.
        player.restructureReliefK = 0
        player.restructureProrationK = 0
        player.restructureCarryYears = 0
        player.isHoldingOut = false
        player.isFranchiseTagged = false
        // The tag year goes with the man. Left behind, it would make his next
        // club's first extension of him a tag replacement — netting a charge
        // nobody is carrying.
        player.franchiseTagSeason = 0
        // #127: a released man's franchise tag is off the books with him. The
        // rollover's `consumeForward` would drop the orphaned row anyway, but a
        // release can happen months before that and every cap projection between
        // now and then would keep charging the club for a player it just cut.
        // Same discipline as the `Contract` row deleted a few lines below: the
        // deal is over, so nothing that describes it may survive.
        CommittedCapLedger.releaseForward(
            playerID: player.id,
            careerID: ContractEngine.resolvedCareerID(careerID, player: player)
        )
        player.trainingFocusArea = nil
        player.trainingPosition = nil
        // §5.1: stamp the release so `PracticeSquadEngine.fillSquads` can honour
        // "own cuts first" and the Revenge Tour storyline can fire.
        player.cutByTeamID = team.id
        player.cutAt = .now

        // The deal is over — the row must not stay in the club's contract map.
        // Fetched rather than trusting the `contract` argument, because a caller
        // that never looked one up would otherwise leave an orphan behind.
        if let modelContext {
            let playerID = player.id
            let descriptor = FetchDescriptor<Contract>(
                predicate: #Predicate<Contract> { $0.playerID == playerID }
            )
            for row in (try? modelContext.fetch(descriptor)) ?? [] {
                modelContext.delete(row)
            }

            recordReleaseReceipt(
                player: player,
                team: team,
                split: split,
                reason: reason,
                seasonYear: seasonYear,
                careerID: ContractEngine.resolvedCareerID(careerID, player: player),
                modelContext: modelContext
            )
        }

        return split
    }

    /// **The release receipt** (#188).
    ///
    /// `CapOverviewView.loadReleaseReceipts` names the dead money on the Cap
    /// screen off `RosterCut` rows, and until now the camp cutdown screen was
    /// the only place in the app that wrote one. Every other release — the
    /// player detail cut, the contract screen, the cap-compliance flow — moved
    /// real money and left the card saying nothing had happened. Writing the
    /// row here, inside the one release authority, is what makes the charge
    /// attributable to a name wherever the cut was made.
    ///
    /// Only the callers that hand over a `ModelContext` file a receipt: the AI
    /// cutdown paths (`WeekAdvancer.trimAIRosters`, `PracticeSquadEngine`,
    /// `ContractEngine.cutPlayer`) pass none, and a league's worth of AI churn
    /// has no business in the user's Cap ledger — nor in the waiver pool that
    /// reads these rows.
    ///
    /// The row is deliberately NOT a camp cut: `cutDayRaw` carries the reason,
    /// not a `CutDay`, so `RosterCutView`'s ladder counts, the camp waiver
    /// sweep and the practice-squad keeper list all skip it (each already
    /// guards with `CutDay(rawValue:)` / `practiceSquadEligible`).
    ///
    /// Idempotent on the receipt key — player, club, league year and reason —
    /// so a double tap, or a release re-run against a man already off the
    /// books, books the charge once.
    private static func recordReleaseReceipt(
        player: Player,
        team: Team,
        split: ReleaseCapSplit,
        reason: ReleaseReason,
        seasonYear: Int?,
        careerID: UUID?,
        modelContext: ModelContext
    ) {
        guard let season = seasonYear ?? currentSeason(careerID: careerID, modelContext: modelContext) else {
            // No league year in reach means no shelf to file the row on: every
            // reader keys on `seasonYear`, so a guessed value would either
            // vanish or land on the wrong season's card.
            return
        }

        let playerID = player.id
        let teamID = team.id
        let descriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> {
                $0.playerID == playerID && $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        guard !existing.contains(where: { $0.cutDayRaw == reason.rawValue }) else { return }

        let cut = RosterCut(
            playerID: playerID,
            teamID: teamID,
            seasonYear: season,
            cutDayRaw: reason.rawValue,
            capSavings: split.capSavings,
            deadCap: split.deadCap,
            practiceSquadEligible: false,
            occurredAt: .now
        )
        cut.releaseReasonRaw = reason.rawValue
        cut.careerID = careerID
        modelContext.insert(cut)
    }

    /// The league year of the save the release belongs to, when the caller did
    /// not state one.
    private static func currentSeason(careerID: UUID?, modelContext: ModelContext) -> Int? {
        guard let careerID else { return nil }
        let descriptor = FetchDescriptor<Career>(
            predicate: #Predicate<Career> { $0.id == careerID }
        )
        return (try? modelContext.fetch(descriptor).first)?.currentSeason
    }

    // MARK: - Cap Growth

    /// Grows the salary cap by the specified annual rate (default ~5% per year in the NFL).
    /// Updates both the team's `salaryCap` and adjusts `currentCapUsage` proportionally
    /// so that available space is preserved in relative terms.
    ///
    /// - Parameters:
    ///   - team: The team whose cap is being updated.
    ///   - growthRate: Fractional growth rate (e.g., 0.05 for 5%). Clamped to 0-0.25.
    static func applyCapGrowth(team: Team, growthRate: Double) {
        let clampedRate = max(0.0, min(0.25, growthRate))
        let oldCap = team.salaryCap
        let newCap = Int(Double(oldCap) * (1.0 + clampedRate))
        team.salaryCap = newCap

        // Cap usage stays the same in absolute terms — the extra headroom is the growth benefit
        // (No adjustment to currentCapUsage needed; the difference is new free space.)
    }

    // MARK: - Cap Space Projection

    /// Projects available cap space after applying the rollover from the previous season.
    ///
    /// - Parameters:
    ///   - team: The team to project for.
    ///   - rolloverAmount: Cap space carried over from the prior year (in thousands).
    /// - Returns: Projected available cap space including rollover.
    static func projectedCapSpace(team: Team, rolloverAmount: Int) -> Int {
        return team.availableCap + rolloverAmount
    }

    /// Cap-mode-aware projection. Sandbox treats cap room as effectively
    /// unlimited so signing UIs never block on availability.
    static func projectedCapSpace(team: Team, rolloverAmount: Int, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return projectedCapSpace(team: team, rolloverAmount: rolloverAmount)
        case .sandbox:
            return Int.max
        }
    }

    /// True if the team can afford a contract of `cost` thousand dollars under
    /// the active cap mode. Sandbox always returns `true`.
    static func canAfford(team: Team, cost: Int, capMode: CapMode) -> Bool {
        switch capMode {
        case .simple, .realistic:
            return team.availableCap >= cost
        case .sandbox:
            return true
        }
    }

    // MARK: - Minimum Salary Floor

    /// Estimates whether the team is meeting the NFL's minimum salary spending requirement
    /// (typically 89% of the cap must be spent over a rolling two-year period).
    ///
    /// - Parameter team: The team to evaluate.
    /// - Returns: `true` if the team appears to be meeting the floor; `false` if at risk.
    static func isAboveSalaryFloor(team: Team) -> Bool {
        let floorThreshold = Int(Double(team.salaryCap) * 0.89)
        return team.currentCapUsage >= floorThreshold
    }

    /// Cap-mode-aware salary floor check. Sandbox always returns `true` — there
    /// is no minimum spend requirement when cap rules are off.
    static func isAboveSalaryFloor(team: Team, capMode: CapMode) -> Bool {
        switch capMode {
        case .simple, .realistic:
            return isAboveSalaryFloor(team: team)
        case .sandbox:
            return true
        }
    }

    /// The dollar amount (in thousands) the team must still spend to reach the salary floor.
    /// Returns 0 if the team is already above the floor.
    static func amountBelowFloor(team: Team) -> Int {
        let floorThreshold = Int(Double(team.salaryCap) * 0.89)
        let shortfall = floorThreshold - team.currentCapUsage
        return max(0, shortfall)
    }

    /// Cap-mode-aware version. Sandbox always returns 0.
    static func amountBelowFloor(team: Team, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return amountBelowFloor(team: team)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Cap Compliance (cap-compliance wave)

    /// Whether a club's books are legal, and by how much they are not.
    ///
    /// Deliberately DERIVED from `Team` on every read rather than stored on the
    /// career. A stored "you are non-compliant" flag is a latch, and a latch is
    /// the one way a cap gate can brick a save: any path that clears the overage
    /// without clearing the flag (a rollover true-up, a trade, an incentive that
    /// did not land, a legacy save loaded into a newer build) leaves the user
    /// permanently blocked with nothing on screen to fix. Derived state cannot
    /// do that — the moment the club is under the cap the gate is gone.
    struct CapComplianceStatus: Equatable {

        /// `Team.availableCap` — negative when the club is over.
        let capRoom: Int

        /// How far over, in thousands. Zero when compliant.
        let overage: Int

        /// False in sandbox, where the cap is switched off by definition.
        let isEnforced: Bool

        var isCompliant: Bool { !isEnforced || overage == 0 }
    }

    /// Reads one club's compliance state.
    static func complianceStatus(team: Team?, capMode: CapMode) -> CapComplianceStatus {
        guard let team, capMode != .sandbox else {
            return CapComplianceStatus(capRoom: 0, overage: 0, isEnforced: false)
        }
        let room = team.availableCap
        return CapComplianceStatus(
            capRoom: room,
            overage: max(0, -room),
            isEnforced: true
        )
    }

    /// Whether the league checks a club's books in this phase.
    ///
    /// The window opens at the league year and stays open. Before the rollover
    /// the club is still carrying LAST year's contracts against last year's cap
    /// — `FreeAgencyEngine.executeNewLeagueYear` has not yet grown the cap, aged
    /// off the dead money or emptied the expiring deals — so an overage measured
    /// in `.superBowl` or `.reviewRoster` is an artefact of a season that has
    /// already been played, not a debt anybody can be asked to settle. Blocking
    /// there would also be a genuine deadlock: the ONE thing that fixes it is
    /// the rollover, and the rollover is on the other side of the block.
    ///
    /// Everything from free agency onward is inside the new league year and is
    /// checked, the regular season included — a club that trades its way over
    /// the cap in November is as illegal as one that signs its way over in
    /// March.
    ///
    /// `.freeAgency` is conditional on the rollover having actually run
    /// (`Career.lastRolloverSeason`), because the phase spans both sides of it:
    /// Final Push happens on the old books, `capReview` onward on the new ones.
    static func isComplianceWindow(phase: SeasonPhase, hasRolledOver: Bool) -> Bool {
        switch phase {
        case .proBowl, .superBowl, .coachingChanges, .reviewRoster, .combine:
            return false
        case .freeAgency:
            return hasRolledOver
        case .proDays, .draft, .otas, .trainingCamp, .preseason,
             .rosterCuts, .regularSeason, .tradeDeadline, .playoffs:
            return true
        }
    }

    /// One way out of an overage, priced.
    ///
    /// The workspace ranks these by ``savings`` and shows the cost beside it,
    /// because the whole decision is a trade between cap now and consequences
    /// later — a release that frees $8M and books $14M of dead money is a
    /// different proposition from a restructure that frees $6M and adds $2M to
    /// each of the next three years, and a list that showed only the savings
    /// column would make them look identical.
    struct ComplianceLever: Identifiable, Equatable {

        enum Kind: String, Equatable {
            case release
            case restructure
        }

        let playerID: UUID
        let playerName: String
        let position: Position
        let overall: Int
        let kind: Kind

        /// Cap freed in the CURRENT league year, in thousands. **Signed**: a
        /// release whose acceleration outruns its relief has negative savings
        /// and is not a way out at all, which the workspace has to be able to
        /// say out loud rather than quietly offer as a fix.
        let savings: Int

        /// Dead money the move books this year (release), or adds to a future
        /// cut (restructure).
        let deadMoney: Int

        /// What the club pays for it in EACH remaining year. Zero for a
        /// release — its whole cost is the dead money above.
        let futureAnnualCharge: Int

        /// Years the future charge runs for.
        let futureYears: Int

        var id: String { "\(kind.rawValue)-\(playerID.uuidString)" }

        /// Whether this lever actually moves the club toward compliance.
        var isEffective: Bool { savings > 0 }
    }

    /// Every lever the club has, ranked by cap freed this year.
    ///
    /// Both kinds are priced by the engines that would execute them —
    /// ``releaseCapSplit`` and `ContractEngine.restructureQuote` — so the number
    /// on the row is the number the button delivers. Nothing here mutates.
    ///
    /// **RENEGOTIATE is deliberately absent.** A pay cut is a conversation, not
    /// a lever: the player can refuse, and what he would accept is
    /// `ContractNegotiationEngine`'s persona model to decide, not this
    /// function's to guess. The workspace links to the Contact Agent chat for
    /// it; a ranked row promising savings the player has not agreed to would be
    /// a plan the user cannot execute.
    static func complianceLevers(
        players: [Player],
        contractsByPlayer: [UUID: Contract],
        capMode: CapMode,
        salaryCap: Int,
        leagueYearRemaining: Double = 1.0
    ) -> [ComplianceLever] {
        guard capMode != .sandbox else { return [] }

        var levers: [ComplianceLever] = []
        levers.reserveCapacity(players.count * 2)

        // #208 G1 — the room every release lever below is measured against.
        // `players` is one club's roster by contract (every caller fetches it on
        // `teamID`), so the positional floors can be asked straight of the
        // evaluator without a `Team` in hand.
        //
        // This is a DEADLOCK guard, not a cosmetic one: `canSelfHeal` reads this
        // list to decide whether the week-advance gate may block the user at
        // all. A lever he is forbidden to pull is not a key, and counting one
        // would hold the save behind a door with nothing on the other side of
        // it — the exact failure mode the camp-body exclusion below was written
        // to avoid.
        let room = players.filter { !$0.isRetired }

        for player in players {
            // A camp body is not a lever (#205a §3.1). He was never charged, so
            // releasing him frees nothing and restructuring him is meaningless —
            // and during the camp phases he is up to a third of the roster, so
            // listing him would bury the twenty rows that CAN move money under
            // twenty-seven that cannot.
            guard !CampRosterEngine.isCampBody(player) else { continue }

            let contract = contractsByPlayer[player.id]

            let releaseBlocked = RosterCutEvaluator.releaseBlockReason(
                player: player,
                roster: room,
                alreadySelected: []
            ) != nil
            if !releaseBlocked {
                let split = releaseCapSplit(
                    player: player,
                    contract: contract,
                    capMode: capMode,
                    leagueYearRemaining: leagueYearRemaining
                )
                levers.append(ComplianceLever(
                    playerID: player.id,
                    playerName: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    kind: .release,
                    savings: split.capSavings,
                    deadMoney: split.deadCap,
                    futureAnnualCharge: 0,
                    futureYears: 0
                ))
            }

            if case .available(let quote) = ContractEngine.restructureQuote(
                player: player,
                contract: contract,
                capMode: capMode,
                salaryCap: salaryCap
            ) {
                levers.append(ComplianceLever(
                    playerID: player.id,
                    playerName: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    kind: .restructure,
                    savings: quote.immediateRelief,
                    deadMoney: quote.deadMoneyAdded,
                    futureAnnualCharge: quote.proratedPerYear,
                    futureYears: max(0, quote.yearsRemaining - 1)
                ))
            }
        }

        return levers.sorted { lhs, rhs in
            if lhs.savings != rhs.savings { return lhs.savings > rhs.savings }
            // Stable tie-break so two identical rows do not swap between reads.
            return lhs.id < rhs.id
        }
    }

    /// The most cap a single lever can free, in thousands. `0` when the club has
    /// no move that helps at all.
    static func bestLeverSavings(_ levers: [ComplianceLever]) -> Int {
        max(0, levers.first?.savings ?? 0)
    }

    /// **The anti-deadlock guarantee.**
    ///
    /// True when at least one lever frees cap. A club whose every contract is so
    /// bonus-heavy that releasing anybody COSTS more than keeping him, and whose
    /// deals are all in their final year so nothing can be restructured, has no
    /// legal way back under the cap this league year — and the honest answer to
    /// that is that the league does not get to freeze the save until March. The
    /// gate lifts, the workspace still shows the overage, and the rollover's
    /// task-#27 true-up (which rebuilds every club's usage from rostered
    /// salaries and ages dead money off) resolves it.
    ///
    /// This is not a loophole worth exploiting: reaching it requires a roster on
    /// which no man can be cut for a gain, which is a roster that has already
    /// cost the user everything the gate would have made him pay.
    static func canSelfHeal(_ levers: [ComplianceLever]) -> Bool {
        levers.contains { $0.isEffective }
    }

    // MARK: - Restructure Façade

    /// The restructure quote, re-exported under the cap engine's name.
    ///
    /// The lever is IMPLEMENTED in `ContractEngine` — that is where a contract's
    /// base salary, its signing bonus and the veteran minimum live, and putting
    /// the arithmetic anywhere else would have meant a second opinion about what
    /// a contract is. But every other cap operation the screens reach for is
    /// spelled `CapManagementEngine.something` (`releaseCapSplit`, `applyRelease`,
    /// `leagueYearRemaining`, `complianceLevers`), so the two forwarders below
    /// let a cap screen keep one import and one vocabulary. They add no logic
    /// and can never disagree with the authority, because they ARE the authority
    /// called with different labels.
    typealias RestructureQuote = ContractEngine.RestructureQuote

    /// ``ContractEngine/restructureQuote(player:contract:capMode:salaryCap:amount:)``,
    /// flattened to an Optional for call sites that only care whether the lever
    /// exists.
    ///
    /// - Parameter salaryCap: the club's CURRENT cap, which sets the veteran
    ///   minimum the conversion floor is measured from. Defaults to the opening
    ///   cap for callers that have not loaded a `Team` yet; since the cap only
    ///   ever grows, that default understates the floor slightly (a ~$200K
    ///   difference by season five on a multi-million-dollar conversion) and so
    ///   errs toward offering the lever rather than hiding it. Pass the real cap
    ///   wherever the team is in hand.
    static func restructureQuote(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        salaryCap: Int = ContractEngine.openingSalaryCap
    ) -> RestructureQuote? {
        ContractEngine.restructureQuote(
            player: player,
            contract: contract,
            capMode: capMode,
            salaryCap: salaryCap
        ).quote
    }

    /// ``ContractEngine/executeRestructure(player:team:contract:capMode:salaryCap:amount:moraleBonus:)``,
    /// with the salary cap read off the club and an optional save.
    ///
    /// - Parameter modelContext: saved when supplied, so a screen that applies
    ///   the lever and then navigates away cannot lose the relief it just
    ///   showed the user.
    @discardableResult
    static func executeRestructure(
        player: Player,
        team: Team?,
        contract: Contract?,
        capMode: CapMode,
        modelContext: ModelContext? = nil
    ) -> RestructureQuote? {
        let applied = ContractEngine.executeRestructure(
            player: player,
            team: team,
            contract: contract,
            capMode: capMode,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
        if applied != nil, let modelContext {
            try? modelContext.save()
        }
        return applied
    }

    // MARK: - AI Symmetry (cap-compliance wave)

    /// Restructures an AI club back under the cap, and stops the instant it is.
    ///
    /// **Why the AI needs this at all.** The gate the user is about to live
    /// under is a rule of the league, not a rule about the user, and a league
    /// where 31 clubs may carry an illegal cap sheet while one may not is not a
    /// simulation of anything. The rollover's task-#27 true-up already rebuilds
    /// every club's usage from rostered salary, so an AI club can still come out
    /// of March over the cap — a fifth-year option picked up on top of a payroll
    /// that had grown into the ceiling, an incentive that landed, a deadline
    /// rental restored to its full base (#45).
    ///
    /// **Why RESTRUCTURE ONLY.** Releases are roster churn, and roster churn is
    /// the calibrated quantity in task #53 — an AI compliance pass that cut
    /// players would move the league's churn shape, the free-agent pool's
    /// denominator and the development numbers that hang off both, to fix a
    /// bookkeeping problem. A restructure moves money and nobody's job.
    ///
    /// **Why it cannot move the market (task #93's reserve discipline).** It
    /// stops at compliance — `availableCap == 0` at best — and the AI free-agent
    /// budget is `availableCap − 15 % of the cap` (`FreeAgencyEngine.capReservePercent`).
    /// A club healed to exactly zero room is still far below its reserve and
    /// still signs nobody. The pass buys legality, never spending power.
    ///
    /// Returns the cap freed, in thousands (0 = nothing to do, or nothing legal
    /// left to do).
    @discardableResult
    static func selfHealCapCompliance(
        team: Team,
        players: [Player],
        contractsByPlayer: [UUID: Contract],
        capMode: CapMode,
        salaryCap: Int
    ) -> Int {
        guard capMode != .sandbox else { return 0 }
        guard team.availableCap < 0 else { return 0 }

        // Biggest relief first, so the fewest contracts are touched. Sorted once
        // and walked, rather than re-ranked per step: the quote for a player who
        // has not been restructured yet does not change when a different player
        // is, so a stable single pass is both cheaper and deterministic.
        let candidates = players
            .compactMap { player -> (Player, ContractEngine.RestructureQuote)? in
                guard case .available(let quote) = ContractEngine.restructureQuote(
                    player: player,
                    contract: contractsByPlayer[player.id],
                    capMode: capMode,
                    salaryCap: salaryCap
                ) else { return nil }
                return (player, quote)
            }
            .sorted { $0.1.immediateRelief > $1.1.immediateRelief }

        var freed = 0
        for (player, _) in candidates {
            guard team.availableCap < 0 else { break }
            let applied = ContractEngine.executeRestructure(
                player: player,
                team: team,
                contract: contractsByPlayer[player.id],
                capMode: capMode,
                salaryCap: salaryCap,
                // An AI club's own accountant asking for a signature is not a
                // moment of goodwill the way a user's GM offering it is.
                moraleBonus: 0
            )
            freed += applied?.immediateRelief ?? 0
        }
        return freed
    }
}
