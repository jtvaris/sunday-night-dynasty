import Foundation
import SwiftData

// MARK: - PracticeSquadEngine

/// The 16-man practice squad and the in-season poaching market (TODO §5.1).
///
/// ## The data shape, and why
///
/// A squad player carries `teamID == nil` and `practiceSquadTeamID == <club>`
/// (see `Player.rosterStatus`). `teamID` is the engine's word for "occupies an
/// active-roster spot", read in ~240 places — the weekly attendance tally,
/// `WeekAdvancer.startingLineupIDs`, the cap ledger, depth charts, trade
/// validation, the offseason development pass. A practice-squad player may not
/// dress on Sunday, so he has to be invisible to every one of them, and hanging
/// the squad off a SECOND id achieves that without touching a single call site.
///
/// The one thing that shape does NOT get for free is the opposite reading:
/// `teamID == nil` also means "free agent" in a handful of places (the FA
/// market, the tampering rumor mill, the AI roster refill). Every one of those
/// additionally requires `contractYearsRemaining == 0`, which is why a squad
/// deal is written with `contractYears` > 0 — a squad player is under contract,
/// exactly as he is in the real league, and is therefore not on the market.
///
/// ## The calendar
///
/// * **Cutdown day** (`.rosterCuts` → `.regularSeason`): every club stocks its
///   squad, own cuts first, then street free agents, and finally — only up to
///   ``squadGenerationFloor`` — invented bodies. ``squadSize`` is a CEILING, not
///   a quota: a club that cannot find sixteen eligible men carries fewer, and
///   measured league-wide the squads run 6-8 deep rather than 16. See
///   ``squadGenerationFloor`` for why that is the honest answer and what the
///   unbounded version cost. `fillSquads`.
/// * **Every regular-season week**: squads develop on the depth rung, AI clubs
///   poach 0-3 players league-wide, and the user is warned a week before one of
///   his own is signed away. `runWeeklyPass`.
/// * **New league year** (`FreeAgencyEngine.executeNewLeagueYear`): the 1-year
///   squad deals expire and the whole league's squads dissolve into free
///   agency, which is what happens to real practice-squad contracts in March.
///   `dissolveSquads`.
///
/// ## Cap treatment
///
/// Squad salary is recorded on the row for display but is **never added to
/// `Team.currentCapUsage`** — practice-squad pay is cap-exempt in the real
/// league, and here that is also the only self-consistent choice: the cap
/// ledger is maintained incrementally and its refund paths all key on
/// `player.teamID != nil`, so a charge made against a `teamID == nil` player
/// could never be refunded and would leak until the league-year true-up.
enum PracticeSquadEngine {

    // MARK: - League Rules

    /// Practice-squad spots per club. The NFL settled at 16 in 2022.
    static let squadSize = 16

    /// Squad men a club will INVENT when the market has nobody left (task #99).
    ///
    /// ## Why a squad is a ceiling and not a quota
    ///
    /// `fillSquads`' last pass used to run `while squad.count < squadSize`,
    /// generating a brand-new `Player` for every unfilled spot. Measured over an
    /// 8-season `PERF_SMOKE_SEASONS` run that pass minted **417 / 250 / 212 / 244
    /// players per season** — a second draft class every year, from nowhere, on
    /// top of the ~250 the real one brings and the AI's undrafted signings.
    ///
    /// Those men are not a curiosity. A squad deal is two contract years
    /// (``contractYears``), so every one of them dissolves into free agency at
    /// the next league year (`FreeAgencyEngine.executeNewLeagueYear` →
    /// ``dissolveSquads``) and lands in the unsigned pool. That is the inflow
    /// half of task #99's shadow pool: the washout pass was strengthened
    /// (`PlayerRetirementEngine.washoutUnprovenFloor` / `washoutSilentMarketFloor`)
    /// and the pool did not shrink, because this door was refilling it as fast
    /// as the exit drained it — measured equilibrium ~900 with the pool's own
    /// clearance running at ~57 %/yr.
    ///
    /// The reason the pool "runs out" is not that the league is short of
    /// footballers. It is that squad eligibility is narrow by RULE — under 70
    /// OVR, three years pro or less unless one of the six ``veteranSlots`` is
    /// spent, three bodies per position — and the unsigned population skews
    /// older than that window (measured mean 5.5 years pro). A club that cannot
    /// find sixteen eligible men has genuinely not found them, and inventing
    /// them is the league telling itself a lie about its own supply.
    ///
    /// So the fallback survives, bounded: a scout team needs enough bodies to
    /// run a look squad in practice, and that is what four is — a unit, not a
    /// roster. Everything above it now has to come from men the league actually
    /// produced. League-wide worst case is 32 × 4 = 128 a season against the
    /// ~250-man draft class, and in practice well under that because the pool
    /// fills the early spots first.
    static let squadGenerationFloor = 4

    /// Active-roster ceiling — a poach signs a man to the 53, so a club must
    /// open a spot for him.
    static let activeRosterCeiling = 53

    /// Weekly squad pay, in thousands (~$216K over a season at the 2024 rookie
    /// practice-squad rate). Recorded for display only; see the cap note above.
    static let squadSalary = 216

    /// Salary a poached player signs for on the ACTIVE roster, in thousands.
    ///
    /// The league minimum, read from the one place it is defined
    /// (``ContractEngine/veteranMinimum(cap:)``) at the opening cap. It used to
    /// be a hand-typed `795` whose doc comment claimed to be that same formula
    /// — it was not: `795` is `0.0030 × 265M` (the UDFA rate), and the veteran
    /// minimum at a $265M cap is `750`.
    ///
    /// Still a constant rather than a function of the club's cap because the
    /// two read sites in `PracticeSquadView` quote it as a plain number; making
    /// the poach price cap-relative is a change to that screen, not to this
    /// engine.
    static let poachSalary = ContractEngine.veteranMinimum(cap: ContractEngine.openingSalaryCap)

    /// Years written onto a squad deal.
    ///
    /// Two, because a contract is decremented TWICE per league cycle — once at
    /// the week-18 tick in `WeekAdvancer` and once at
    /// `FreeAgencyEngine.executeNewLeagueYear`. A squad deal signed on cutdown
    /// day therefore reads 2 → 1 at the end of the regular season (still under
    /// contract, still off the market, which is what a squad player is in
    /// January) and 1 → 0 at the new league year, where it expires and he hits
    /// free agency. That is the real practice-squad calendar, and it falls out
    /// of the existing bookkeeping without a special case anywhere.
    static let contractYears = 2

    /// Vested veterans a club may stash. The real rule allows six players with
    /// no free-agency-eligibility limit; everyone else must be an early-career
    /// player. Modelled on `yearsPro` rather than accrued seasons.
    static let veteranSlots = 6

    /// `yearsPro` at or below which a player is squad-eligible without using
    /// one of the six veteran slots.
    static let youngPlayerYearsPro = 3

    /// Most bodies a squad may carry at one position — nobody stashes five
    /// quarterbacks.
    static let maxPerPosition = 3

    /// Most quarterbacks on a squad.
    static let maxQuarterbacks = 2

    // MARK: - AI Poaching Volume

    /// Weekly league-wide poach count, drawn per week. Mean ≈ 1.4, so a
    /// full 18-week season runs ~25 poaches league-wide — a shade under one per
    /// club per season, which is the order the real transaction wire moves at
    /// (most clubs sign one or two squad players off other rosters a year, and
    /// a few sign none).
    static func weeklyPoachTarget() -> Int {
        switch Double.random(in: 0..<1) {
        case ..<0.20: return 0
        case ..<0.55: return 1
        case ..<0.85: return 2
        default:      return 3
        }
    }

    /// Chance per week that a rival files interest in one of the USER's squad
    /// players. Deliberately low: the warning is a decision moment, and a
    /// decision moment every week is noise.
    static let userPoachInterestChance = 0.18

    // MARK: - Pending Poaches (the user's warning window)

    /// A rival has filed interest in one of the user's squad players; the
    /// signing lands NEXT week unless the user promotes him first.
    struct PendingPoach {
        let playerID: UUID
        let suitorTeamID: UUID
        let seasonYear: Int
        let filedWeek: Int
    }

    /// In-memory, like `FASigningTracker` and `TradeValueEngine.TradeTalkRegistry`.
    ///
    /// Losing this to a relaunch means a warned player simply is not signed
    /// away — the failure mode is "the user keeps his guy", never a silent
    /// transaction he was not told about, so a persisted row would buy nothing
    /// but a schema migration.
    private(set) static var pendingUserPoaches: [PendingPoach] = []

    /// Clears the warning window — called on career switch and new season.
    static func reset() {
        pendingUserPoaches = []
    }

    // MARK: - Result Types

    /// One completed signing, for news and mail.
    struct PoachResult {
        let playerID: UUID
        let playerName: String
        let position: Position
        let overall: Int
        let fromTeamID: UUID
        let fromAbbreviation: String
        let toTeamID: UUID
        let toAbbreviation: String
        let toTeamName: String
    }

    /// A rival's filed interest, for the warning mail.
    struct PoachWarning {
        let playerID: UUID
        let playerName: String
        let position: Position
        let suitorAbbreviation: String
        let suitorName: String
    }

    /// What one weekly pass did.
    struct WeeklyOutcome {
        var poaches: [PoachResult] = []
        var userLosses: [PoachResult] = []
        var warnings: [PoachWarning] = []
        var developed: Int = 0
    }

    /// What one cutdown-day fill did.
    struct FillSummary {
        var clubsFilled: Int = 0
        var fromOwnCuts: Int = 0
        var fromStreetFreeAgents: Int = 0
        var generated: Int = 0

        var totalSignings: Int { fromOwnCuts + fromStreetFreeAgents + generated }
    }

    // MARK: - Queries

    /// Every player currently stashed on `teamID`'s squad, best first.
    static func squad(of teamID: UUID, in allPlayers: [Player]) -> [Player] {
        allPlayers
            .filter { $0.practiceSquadTeamID == teamID && $0.isOnPracticeSquad && !$0.isRetired }
            .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
    }

    /// Every squad player in the league EXCEPT `excludingTeamID`'s own — the
    /// browsable poach board. Sorted by keep-score so the men worth taking are
    /// at the top.
    static func leagueSquad(excluding excludingTeamID: UUID?, in allPlayers: [Player]) -> [Player] {
        allPlayers
            .filter { $0.isOnPracticeSquad && !$0.isRetired && $0.practiceSquadTeamID != excludingTeamID }
            .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
    }

    /// Players occupying `teamID`'s ACTIVE roster.
    static func activeRoster(of teamID: UUID, in allPlayers: [Player]) -> [Player] {
        allPlayers.filter { $0.teamID == teamID && !$0.isRetired }
    }

    /// Whether a player may be stashed on a squad at all.
    ///
    /// `usedVeteranSlots` is the club's current count of stashed players past
    /// `youngPlayerYearsPro`; once it reaches `veteranSlots` only early-career
    /// players qualify.
    static func isSquadEligible(_ player: Player, usedVeteranSlots: Int) -> Bool {
        guard !player.isRetired, !player.isOnPracticeSquad, player.teamID == nil else { return false }
        // A man good enough to start somewhere does not accept squad money.
        guard player.overall < startingCalibreOverall else { return false }
        if player.yearsPro <= youngPlayerYearsPro { return true }
        return usedVeteranSlots < veteranSlots
    }

    /// OVR at which a free agent would rather wait for an active-roster offer
    /// than take squad money. Set just below the league's starter band so the
    /// squad fills with fringe bodies rather than with players the 53 wants.
    static let startingCalibreOverall = 70

    // MARK: - Cutdown Day

    /// Fills every club's practice squad on cutdown day, own cuts first.
    ///
    /// ORDERING (load-bearing): this runs AFTER `WeekAdvancer.startNewSeason`,
    /// i.e. after `refillAIRosters` has topped every active roster back up to
    /// 53 out of the free-agent pool. Run before it and the refill — which
    /// filters on `teamID == nil` and sorts by the same keep-score used here —
    /// would strip the best man off every squad the moment it was assembled.
    ///
    /// - Returns: a summary for the caller's log.
    @discardableResult
    static func fillSquads(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) -> FillSummary {
        var summary = FillSummary()

        // Anything left over from a previous season (an interrupted advance, a
        // restored save) is cleared first: a squad is assembled fresh every
        // cutdown day, exactly like the 53 above it.
        dissolveSquads(allPlayers: allPlayers)

        // One shared pool. `taken` keeps the 32 clubs from all signing the same
        // man, and the ordering inside each club's pass is need-first.
        var taken = Set<UUID>()
        let pool = allPlayers.filter {
            $0.teamID == nil && !$0.isRetired && !$0.isOnPracticeSquad
                && $0.overall < startingCalibreOverall
        }

        // The user's own answer to "who do we keep developing": the players he
        // ticked as practice-squad-eligible while working the 90 → 53 cut flow
        // (`RosterCutView` writes `RosterCut.practiceSquadEligible`). Until this
        // existed that tick did nothing at all.
        let keeperIDs = userFlaggedKeepers(career: career, modelContext: modelContext)

        // Fetch order is not a signing order. Each club's pass takes the best
        // remaining men out of ONE shared pool, so iterating `teams` as they came
        // out of the store gave the earliest-indexed clubs first refusal on the
        // whole market every cutdown day — and, now that the invented-body
        // fallback is bounded, it would also concentrate the SHORT squads on the
        // same late clubs every season. Same argument, same fix as
        // `WeekAdvancer.refillAIStaffVacancies`: with no ordering that means
        // anything, the honest answer is a coin toss.
        for team in teams.shuffled() {
            let roster = activeRoster(of: team.id, in: allPlayers)
            var squad: [Player] = []
            var veteransUsed = 0
            var countByPosition: [Position: Int] = [:]

            /// Own cuts first — the club knows these bodies, and every real
            /// squad is built out of the men it just released. `cutByTeamID` is
            /// stamped by the user's cut flow (`WaiverWireEngine`) and by the
            /// AI cutdown (`WeekAdvancer.trimAIRosters`).
            func rank(_ player: Player) -> Double {
                let own = player.cutByTeamID == team.id ? 1_000.0 : 0.0
                return own + RosterValue.keepScore(player)
            }

            func canAdd(_ player: Player) -> Bool {
                guard !taken.contains(player.id) else { return false }
                // A man the user flagged as a keeper is spoken for: with the
                // club order now shuffled, an AI club drawn before the user's
                // could otherwise lift a cut-and-flagged keeper out of the
                // shared pool before Pass 0 ever ran for him.
                guard team.id == career.teamID || !keeperIDs.contains(player.id) else { return false }
                guard isSquadEligible(player, usedVeteranSlots: veteransUsed) else { return false }
                let cap = player.position == .QB ? maxQuarterbacks : maxPerPosition
                return (countByPosition[player.position] ?? 0) < cap
            }

            func add(_ player: Player, keeper: Bool = false) {
                stash(player, on: team.id)
                taken.insert(player.id)
                squad.append(player)
                countByPosition[player.position, default: 0] += 1
                if player.yearsPro > youngPlayerYearsPro { veteransUsed += 1 }
                if keeper || player.cutByTeamID == team.id {
                    summary.fromOwnCuts += 1
                } else {
                    summary.fromStreetFreeAgents += 1
                }
            }

            // Pass 0: the user's flagged keepers, ahead of everything.
            //
            // These are the only squad signings that can come off an ACTIVE
            // roster, which is the whole point — the user marked them while
            // deciding who to release, so stashing one IS the release, and his
            // cap charge has to come back off the ledger with him. The OVR gate
            // in `isSquadEligible` is deliberately not applied: the user is
            // allowed to stash a better player than the AI would, at the cost of
            // the roster spot he just gave up.
            if team.id == career.teamID, !keeperIDs.isEmpty {
                let keepers = allPlayers
                    .filter { keeperIDs.contains($0.id) && !$0.isRetired && !$0.isOnPracticeSquad }
                    .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
                for keeper in keepers where squad.count < squadSize {
                    guard !taken.contains(keeper.id) else { continue }
                    let positionCap = keeper.position == .QB ? maxQuarterbacks : maxPerPosition
                    guard (countByPosition[keeper.position] ?? 0) < positionCap else { continue }
                    if keeper.yearsPro > youngPlayerYearsPro, veteransUsed >= veteranSlots { continue }
                    if keeper.teamID == team.id, career.capMode != .sandbox {
                        team.currentCapUsage -= keeper.annualSalary
                    }
                    add(keeper, keeper: true)
                }
            }

            // Pass 1: cover the club's thinnest position groups, so a squad is
            // insurance rather than a pile of whoever rated highest.
            for position in DraftEngine.topTeamNeeds(roster: roster, limit: 6) {
                guard squad.count < squadSize else { break }
                let candidates = pool
                    .filter { $0.position == position && canAdd($0) }
                    .sorted { rank($0) > rank($1) }
                if let best = candidates.first { add(best) }
            }

            // Pass 2: best available until the squad is full.
            let ranked = pool.sorted { rank($0) > rank($1) }
            for player in ranked where squad.count < squadSize {
                guard canAdd(player) else { continue }
                add(player)
            }

            // Pass 3: the pool ran dry — street free agents report for a
            // tryout, the same fallback `refillAIRosters` uses when the market
            // has nothing left. Bounded at ``squadGenerationFloor``: a short
            // squad is the honest reading of an empty market, and an unbounded
            // one here was the league's largest single source of invented
            // population (see the constant).
            while squad.count < squadGenerationFloor {
                let needs = DraftEngine.topTeamNeeds(roster: roster + squad, limit: 3)
                let position = needs.first(where: {
                    ($0 == .QB ? maxQuarterbacks : maxPerPosition) > (countByPosition[$0] ?? 0)
                }) ?? .WR
                let generated = LeagueGenerator.generatePlayer(
                    position: position,
                    teamID: team.id,
                    depthIndex: 3
                )
                generated.teamID = nil
                generated.careerID = career.id
                modelContext.insert(generated)
                stash(generated, on: team.id)
                squad.append(generated)
                countByPosition[position, default: 0] += 1
                summary.generated += 1
            }

            if !squad.isEmpty { summary.clubsFilled += 1 }
        }

        return summary
    }

    /// Player ids the user ticked as practice-squad-eligible during this
    /// cutdown, newest first.
    ///
    /// Season window: `fillSquads` runs at the `.rosterCuts` → `.regularSeason`
    /// boundary, and `career.currentSeason` has already been incremented by the
    /// time it does, while the `RosterCut` rows were written under the OLD year.
    /// Accepting both years is what makes the lookup independent of where in
    /// that boundary the caller sits.
    private static func userFlaggedKeepers(
        career: Career,
        modelContext: ModelContext
    ) -> Set<UUID> {
        guard let teamID = career.teamID else { return [] }
        let cid = career.id
        // Three `&&` clauses is the most `#Predicate` type-checks comfortably
        // here (see `FreeAgencyView.loadData`); the season window is applied on
        // the already-tiny result.
        let descriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> {
                $0.careerID == cid && $0.teamID == teamID && $0.practiceSquadEligible
            }
        )
        let cuts = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.seasonYear >= career.currentSeason - 1 }
            .sorted { $0.occurredAt > $1.occurredAt }
        return Set(cuts.prefix(squadSize).map(\.playerID))
    }

    // MARK: - Roster Moves

    /// Writes the practice-squad state onto a player: off the active roster,
    /// onto `teamID`'s squad, on a cap-exempt 1-league-year deal.
    static func stash(_ player: Player, on teamID: UUID) {
        player.teamID = nil
        player.practiceSquadTeamID = teamID
        player.rosterStatus = .practiceSquad
        player.contractYearsRemaining = contractYears
        player.annualSalary = squadSalary
        player.isFranchiseTagged = false
        player.isHoldingOut = false
        player.trainingFocusArea = nil
        player.trainingPosition = nil
    }

    /// Signs a squad player onto an ACTIVE roster — the one and only way a
    /// player leaves a squad while the season is running.
    ///
    /// Used for BOTH halves of the mechanic, because in the NFL they are the
    /// same transaction: a club "elevating" its own squad player and a club
    /// "poaching" a rival's both sign him to the 53 at the active minimum.
    /// There is no squad-to-squad move, by rule and here.
    ///
    /// - Parameter leagueYearRemaining: The share of the league year still
    ///   unpaid, from `CapManagementEngine.leagueYearRemaining(phase:week:)`.
    ///   This is an IN-SEASON transaction — the whole mechanic only runs during
    ///   the regular season — so the corresponding release must be priced under
    ///   the same #26 midseason rule the four user-facing cut screens use, not
    ///   under the full-year default. Leaving it at 1.0 made this the one
    ///   release path in the game that handed a club back base salary it had
    ///   already spent, and it did so at Week 17 as readily as at Week 1.
    ///
    /// - Returns: `false` when the club has no room it is willing to make.
    @discardableResult
    static func signToActiveRoster(
        _ player: Player,
        to team: Team,
        allPlayers: [Player],
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> Bool {
        guard player.isOnPracticeSquad else { return false }

        // A 53-man roster has to give a spot back. Real clubs make a
        // corresponding move; here the club releases its own lowest keep-score
        // body, which is the same sort key cutdown day uses.
        let roster = activeRoster(of: team.id, in: allPlayers)
        var release: Player?
        if roster.count >= activeRosterCeiling {
            release = roster
                .filter { !$0.isInjured }
                .min(by: { RosterValue.keepScore($0) < RosterValue.keepScore($1) })
            guard release != nil else { return false }
        }

        // Afford the deal BEFORE anybody is released — the corresponding move
        // frees the released man's salary, so it has to be part of the sum, and
        // failing the test after the cut would leave the club a man short with
        // nothing signed.
        if capMode != .sandbox {
            // The corresponding move frees `capSavings`, NOT the whole salary:
            // the released man's bonus acceleration stays on the books (#68).
            // Same `leagueYearRemaining` the execution below books, so preview
            // and ledger cannot disagree.
            let freed = release.map {
                CapManagementEngine.releaseCapSplit(
                    player: $0,
                    contract: nil,
                    capMode: capMode,
                    leagueYearRemaining: leagueYearRemaining
                ).capSavings
            } ?? 0
            let projected = team.availableCap + freed
            guard projected >= poachSalary else { return false }
        }

        if let release {
            // `applyRelease` directly rather than `ContractEngine.cutPlayer`,
            // which has no way to carry the midseason share — and it already
            // stamps `cutByTeamID` / `cutAt`.
            CapManagementEngine.applyRelease(
                player: release,
                team: team,
                capMode: capMode,
                leagueYearRemaining: leagueYearRemaining
            )
        }

        player.practiceSquadTeamID = nil
        player.rosterStatus = .active
        ContractEngine.signPlayer(
            player: player,
            years: 1,
            annualSalary: poachSalary,
            team: team,
            capMode: capMode
        )
        return true
    }

    /// Releases a squad player outright — back into the free-agent pool.
    static func release(_ player: Player) {
        player.practiceSquadTeamID = nil
        player.rosterStatus = .active
        player.contractYearsRemaining = 0
        player.annualSalary = 0
    }

    /// Ends every squad in the league, turning each stashed player into a plain
    /// free agent. Called at the new league year, and defensively at the top of
    /// `fillSquads`.
    static func dissolveSquads(allPlayers: [Player]) {
        for player in allPlayers where player.practiceSquadTeamID != nil || player.rosterStatus == .practiceSquad {
            release(player)
        }
        pendingUserPoaches = []
    }

    /// Self-healing pass: a squad marker can only ever be stale in one
    /// direction — some other system (the AI roster refill, a waiver claim,
    /// `LeagueTemplateImporter`) put the player back on an active roster
    /// without knowing about squads. Clearing the marker keeps the two ids from
    /// ever disagreeing.
    ///
    /// - Returns: how many rows were repaired.
    @discardableResult
    static func reconcile(allPlayers: [Player]) -> Int {
        var repaired = 0
        for player in allPlayers {
            guard player.practiceSquadTeamID != nil || player.rosterStatus == .practiceSquad else { continue }
            if player.teamID != nil || player.isRetired || player.practiceSquadTeamID == nil {
                release(player)
                repaired += 1
            }
        }
        if repaired > 0 {
            let live = Set(allPlayers.filter { $0.isOnPracticeSquad }.map(\.id))
            pendingUserPoaches.removeAll { !live.contains($0.playerID) }
        }
        return repaired
    }

    // MARK: - Weekly Pass

    /// One regular-season week of practice-squad life: reps, rival interest,
    /// and signings.
    static func runWeeklyPass(
        career: Career,
        teams: [Team],
        allPlayers: [Player]
    ) -> WeeklyOutcome {
        var outcome = WeeklyOutcome()
        _ = reconcile(allPlayers: allPlayers)

        // Every release this pass books is an in-season corresponding move, so
        // it is priced on the game checks still to come (#26 / #68).
        let leagueYearRemaining = CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
        let teamsByID = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        outcome.developed = applyPracticeReps(allPlayers: allPlayers)

        // 1. Warnings filed LAST week come due now — the user had his window.
        outcome.userLosses = resolvePendingPoaches(
            career: career,
            teamsByID: teamsByID,
            allPlayers: allPlayers,
            leagueYearRemaining: leagueYearRemaining
        )
        outcome.poaches.append(contentsOf: outcome.userLosses)

        // 2. This week's league-wide churn. AI clubs sign from AI squads
        //    immediately; the user's squad is only ever WARNED here.
        var budget = max(0, weeklyPoachTarget() - outcome.userLosses.count)
        var suitors = teams
            .filter { $0.id != career.teamID }
            .shuffled()

        while budget > 0, let suitor = suitors.popLast() {
            let roster = activeRoster(of: suitor.id, in: allPlayers)
            let needs = shorthandedPositions(roster: roster)
            guard !needs.isEmpty else { continue }

            let board = leagueSquad(excluding: suitor.id, in: allPlayers)
                .filter { needs.contains($0.position) && !isWarned($0.id) }
            guard let target = board.first, let loser = target.practiceSquadTeamID else { continue }

            // The user's own squad is never raided without notice.
            if loser == career.teamID {
                guard outcome.warnings.isEmpty,
                      Double.random(in: 0..<1) < userPoachInterestChance else { continue }
                pendingUserPoaches.append(PendingPoach(
                    playerID: target.id,
                    suitorTeamID: suitor.id,
                    seasonYear: career.currentSeason,
                    filedWeek: career.currentWeek
                ))
                outcome.warnings.append(PoachWarning(
                    playerID: target.id,
                    playerName: target.fullName,
                    position: target.position,
                    suitorAbbreviation: suitor.abbreviation,
                    suitorName: suitor.fullName
                ))
                continue
            }

            guard let loserTeam = teamsByID[loser] else { continue }
            guard signToActiveRoster(
                target,
                to: suitor,
                allPlayers: allPlayers,
                capMode: career.capMode,
                leagueYearRemaining: leagueYearRemaining
            ) else { continue }

            outcome.poaches.append(result(
                player: target,
                from: loserTeam,
                to: suitor
            ))
            budget -= 1
        }

        return outcome
    }

    /// Executes the poaches the user was warned about a week ago.
    private static func resolvePendingPoaches(
        career: Career,
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        leagueYearRemaining: Double
    ) -> [PoachResult] {
        guard !pendingUserPoaches.isEmpty else { return [] }

        let playersByID = Dictionary(allPlayers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var landed: [PoachResult] = []
        var stillPending: [PendingPoach] = []

        for pending in pendingUserPoaches {
            // A warning is only good for the week it was filed in — a stale one
            // (season rolled over, the user sat on the mail for a month) simply
            // lapses rather than firing late.
            guard pending.seasonYear == career.currentSeason,
                  career.currentWeek <= pending.filedWeek + 1 else { continue }
            guard career.currentWeek > pending.filedWeek else {
                stillPending.append(pending)
                continue
            }
            guard let target = playersByID[pending.playerID],
                  target.isOnPracticeSquad,
                  let loserID = target.practiceSquadTeamID,
                  let loserTeam = teamsByID[loserID],
                  let suitor = teamsByID[pending.suitorTeamID] else { continue }

            guard signToActiveRoster(
                target,
                to: suitor,
                allPlayers: allPlayers,
                capMode: career.capMode,
                leagueYearRemaining: leagueYearRemaining
            ) else { continue }

            landed.append(result(player: target, from: loserTeam, to: suitor))
        }

        pendingUserPoaches = stillPending
        return landed
    }

    /// Whether a squad player already has a rival's interest on file.
    private static func isWarned(_ playerID: UUID) -> Bool {
        pendingUserPoaches.contains { $0.playerID == playerID }
    }

    private static func result(player: Player, from loser: Team, to suitor: Team) -> PoachResult {
        PoachResult(
            playerID: player.id,
            playerName: player.fullName,
            position: player.position,
            overall: player.overall,
            fromTeamID: loser.id,
            fromAbbreviation: loser.abbreviation,
            toTeamID: suitor.id,
            toAbbreviation: suitor.abbreviation,
            toTeamName: suitor.fullName
        )
    }

    // MARK: - Need Detection

    /// Position groups where a club is genuinely short-handed THIS week —
    /// which, on a roster that is always exactly 53, means injuries.
    ///
    /// Counted over the AVAILABLE roster against the same ideal group sizes the
    /// free-agent market prices need with (`FreeAgencyEngine.positionGroupInfo`),
    /// so "we need a corner" means the same thing in both markets.
    static func shorthandedPositions(roster: [Player]) -> [Position] {
        let available = roster.filter { !$0.isInjured && !$0.isHoldingOut && !$0.isRetired }
        var short: [Position] = []
        for position in Position.allCases {
            let (group, ideal) = FreeAgencyEngine.positionGroupInfo(for: position)
            let count = available.filter { group.contains($0.position) }.count
            if count < ideal { short.append(position) }
        }
        return short
    }

    // MARK: - Development

    /// The squad's week of work: practice reps on the bottom rung of task #29's
    /// playing-time ladder.
    ///
    /// `DEVELOPMENT_NFL_REFERENCE.md` §6 asks for "a practice-reps floor, not
    /// zero" for the men who never dress, and `PlayingTimeRole.depth` is
    /// exactly that floor (8 % of a starter's credit). This is the same weekly
    /// `applyGameExperience` call the active roster gets in `WeekAdvancer`, run
    /// over the disjoint squad population — a squad player has `teamID == nil`
    /// and is therefore absent from that pass, so nobody is credited twice.
    ///
    /// - Returns: how many squad players took reps.
    @discardableResult
    static func applyPracticeReps(allPlayers: [Player]) -> Int {
        let squadPlayers = allPlayers.filter {
            $0.isOnPracticeSquad && !$0.isInjured && !$0.isRetired
        }
        for player in squadPlayers {
            PlayerDevelopmentEngine.applyGameExperience(
                player,
                gamesPlayed: 1,
                gamesStarted: 0,
                startCredit: PlayerDevelopmentEngine.PlayingTimeRole.depth.startCreditShare
            )
        }
        return squadPlayers.count
    }
}
