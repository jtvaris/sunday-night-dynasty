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
/// * **Cutdown day** (`.rosterCuts` → `.regularSeason`): the 32 clubs deal the
///   unsigned market round-robin, one man each per round, own cuts first; only
///   a club still under ``squadGenerationFloor`` when the market is empty
///   invents anybody. ``squadSize`` is a CEILING, not a quota: a club that
///   cannot find sixteen eligible men carries fewer. See
///   ``squadGenerationFloor`` for what the unbounded version cost and
///   ``accruedSeasonsLimit`` for why the eligibility rule — not the market —
///   was what held the league to 6-8 deep. `fillSquads`.
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
    /// footballers — that reading held for one wave and task #144 measured it
    /// wrong. It was the RULE: eligibility keyed on `yearsPro`, which ticks for
    /// unsigned men exactly as fast as for starters, so the ~171 sub-70 men on
    /// the street every August could only be signed against 32 × 6 = 192
    /// veteran slots, and the ceiling on the whole league's squads was
    /// arithmetic. See ``accruedSeasonsLimit``, which is the rule the league
    /// office actually writes it in.
    ///
    /// So the fallback survives, bounded: a scout team needs enough bodies to
    /// run a look squad in practice, and that is what four is — a unit, not a
    /// roster. Everything above it has to come from men the league actually
    /// produced. League-wide worst case is 32 × 4 = 128 a season against the
    /// ~250-man draft class; measured after #144 it runs at ~0, because the
    /// round-robin deal spreads a market that the old club-at-a-time pass let
    /// the first few clubs empty.
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
    /// no free-agency-eligibility limit; everyone else must be inside the
    /// service window (``accruedSeasonsLimit``).
    ///
    /// **What a veteran slot is worth is measured on `RosterValue.keepScore`,
    /// not on raw OVR** (task #144). ``startingCalibreOverall`` — "a man good
    /// enough to start somewhere does not accept squad money" — is the right
    /// idea and the wrong number for this cohort, because a 30-year-old at 74
    /// is not starting anywhere in this league: cutdown day and the roster
    /// refill both rank him on `keepScore`, where his age discount puts him at
    /// 58, behind a fourth-round rookie. Measured over an 8-season smoke that
    /// left 176-207 unsigned men at a mean OVR of 74.1 and a mean age of 30.9
    /// standing on the street in August while clubs INVENTED squad bodies to
    /// reach the generation floor. Judging the six on the same key the 53 is
    /// chosen with makes "nobody's 53 wants him" the test for both, which is
    /// what it already was in fact.
    static let veteranSlots = 6

    /// `yearsPro` at or below which a player is squad-eligible without using
    /// one of the six veteran slots.
    ///
    /// Kept as the fast path beside the real ``accruedSeasonsLimit`` test: a
    /// man three calendar years into his career is early-career whatever his
    /// participation says, and a rookie has no `PlayerSeasonHistory` rows to
    /// read at all.
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

        // --- Supply diagnostics (task #144) ---------------------------------
        //
        // `totalSignings` alone cannot tell "the market was thin" from "the
        // eligibility rule bit": both read as a short squad. These four count
        // the pool the fill was handed, split on the two gates that actually
        // decide a seat — the OVR ceiling and the service window.

        /// Unsigned, unretired men the market offered this cutdown.
        var poolSize: Int = 0
        /// …of whom fill an UNRESTRICTED seat (no veteran slot needed).
        var poolYoung: Int = 0
        /// …of whom carry a `cutByTeamID` stamp (somebody released them).
        var poolCut: Int = 0
        /// Per-club squad depth after the fill, for the league distribution.
        var squadDepths: [Int] = []
        /// League-wide veteran slots spent, against the 32 × `veteranSlots`
        /// ceiling — the number that says whether the six-man exception is the
        /// binding constraint or merely present.
        var veteranSlotsUsed: Int = 0

        var totalSignings: Int { fromOwnCuts + fromStreetFreeAgents + generated }

        var averageDepth: Double {
            squadDepths.isEmpty ? 0
                : Double(squadDepths.reduce(0, +)) / Double(squadDepths.count)
        }

        /// One line, printed by `fillSquads` itself so the measurement travels
        /// with the engine rather than with whichever caller happens to run it.
        var diagnosticLine: String {
            let sorted = squadDepths.sorted()
            return String(
                format: "[PracticeSquad] diag depth avg=%.1f min=%d max=%d "
                    + "clubsAtCeiling=%d | pool n=%d unrestricted=%d cut=%d "
                    + "| vetSlots %d/%d | signings own=%d street=%d minted=%d",
                averageDepth, sorted.first ?? 0, sorted.last ?? 0,
                squadDepths.filter { $0 >= squadSize }.count,
                poolSize, poolYoung, poolCut,
                veteranSlotsUsed, squadDepths.count * veteranSlots,
                fromOwnCuts, fromStreetFreeAgents, generated
            )
        }
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
    /// `usedVeteranSlots` is the club's current count of stashed players who
    /// needed one of the six ``veteranSlots``; once it reaches `veteranSlots`
    /// only unrestricted players qualify. `accruedSeasons` is the player's
    /// career count of ``accruedSeasonGames``-game seasons — see
    /// ``accruedSeasonsLimit`` for why the rule turns on that and not on
    /// `yearsPro` alone.
    static func isSquadEligible(
        _ player: Player,
        usedVeteranSlots: Int,
        accruedSeasons: Int
    ) -> Bool {
        guard !player.isRetired, !player.isOnPracticeSquad, player.teamID == nil else { return false }

        // The unrestricted seats: early-career by the calendar OR by the rule
        // book. Either way a man good enough to start somewhere does not accept
        // squad money.
        if player.yearsPro <= youngPlayerYearsPro || accruedSeasons <= accruedSeasonsLimit {
            return player.overall < startingCalibreOverall
        }

        // One of the six. Judged on the key the 53 itself is chosen with, not on
        // raw OVR — see ``veteranSlots``.
        guard usedVeteranSlots < veteranSlots else { return false }
        return RosterValue.keepScore(player) < Double(startingCalibreOverall)
    }

    /// Whether `player` needs one of the six ``veteranSlots`` to be stashed.
    static func needsVeteranSlot(_ player: Player, accruedSeasons: Int) -> Bool {
        player.yearsPro > youngPlayerYearsPro && accruedSeasons > accruedSeasonsLimit
    }

    /// OVR at which a free agent would rather wait for an active-roster offer
    /// than take squad money. Set just below the league's starter band so the
    /// squad fills with fringe bodies rather than with players the 53 wants.
    static let startingCalibreOverall = 70

    // MARK: - Accrued Seasons (task #144)

    /// Regular-season games on an active roster that make a season "accrued".
    /// The real rule is six; `PlayerSeasonHistory.gamesPlayed` is the game's
    /// only league-wide participation signal (#33) and it counts exactly that —
    /// weeks the man was on a 53 and available.
    static let accruedSeasonGames = 6

    /// Accrued seasons at or below which a player fills an UNRESTRICTED squad
    /// seat, no veteran slot spent.
    ///
    /// ## Why the rule had to stop reading `yearsPro`
    ///
    /// The NFL's practice-squad rule is written in ACCRUED SEASONS, and a
    /// season on a practice squad does not accrue one. That is not a detail —
    /// it is the entire reason practice-squad careers exist: a man can spend
    /// four years bouncing between squads, never dress on a Sunday, and remain
    /// eligible for an unrestricted seat the whole time. Only ``veteranSlots``
    /// is about experience, and it is about the experience of having HELD A JOB.
    ///
    /// This engine modelled the rule on `yearsPro` — calendar years since entry
    /// — which is the one thing that keeps ticking whether a man plays or not.
    /// `WeekAdvancer`'s offseason pass ages every unrostered player
    /// (`applyAgeRegression` for anyone `teamID == nil`), so a squad body's
    /// clock advanced exactly as fast as a ten-year starter's, and after four
    /// calendar years he could only be signed against one of the six.
    ///
    /// **Measured, 8-season `PERF_SMOKE_SEASONS` run, before this change.** The
    /// unsigned market at stocking time held 190-202 sub-70 men of whom only
    /// 19-32 were inside the `yearsPro` window; the other ~171 all had to come
    /// out of 32 × 6 = 192 veteran slots. Squads ran 6.3-6.7 of 16 and the
    /// arithmetic ceiling on the old rule was `(192 + ~25) / 32 = 6.8` — i.e.
    /// the fill was already taking EVERY man it was allowed to take (own cuts +
    /// street signings summed to the pool count exactly, season after season).
    /// Not a market shortage and not a preference bug: the rule itself was the
    /// binding constraint, and it was binding because it was the wrong rule.
    ///
    /// Two, the real number. A player with three or more accrued seasons is a
    /// veteran-slot signing here exactly as he is in the league office.
    static let accruedSeasonsLimit = 2

    /// Accrued-season counts for the whole save, by player id.
    ///
    /// One fetch of `PlayerSeasonHistory` — the same store
    /// `WeekAdvancer.processWashouts` reads for peak ratings — folded into a
    /// dictionary. `recordSeasonHistory` writes a row for EVERY unretired
    /// player at week 18, including free agents and squad men, and
    /// `gamesPlayedThisSeason` is only ever incremented for a man on a 53, so a
    /// year spent unsigned or stashed lands as a `gamesPlayed == 0` row and
    /// correctly accrues nothing. A player with no rows at all — this season's
    /// rookie class — has no accrued seasons either.
    static func accruedSeasonsByPlayer(
        career: Career,
        modelContext: ModelContext
    ) -> [UUID: Int] {
        let cid = career.id
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate<PlayerSeasonHistory> { $0.careerID == cid }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var counts: [UUID: Int] = [:]
        for row in rows where row.gamesPlayed >= accruedSeasonGames {
            counts[row.playerID, default: 0] += 1
        }
        return counts
    }

    // MARK: - Cutdown Day

    /// One club's in-progress squad while the round-robin runs.
    private struct ClubFill {
        let team: Team
        let roster: [Player]
        var squad: [Player] = []
        var veteransUsed = 0
        var countByPosition: [Position: Int] = [:]
        /// Set the first round this club finds nothing it may add. Sound as a
        /// latch because every gate only ever tightens: `taken` grows, the
        /// position counts grow, the veteran slots fill, and the candidate list
        /// shrinks — a club that cannot sign anybody now cannot later either.
        var isDone = false
    }

    /// Fills every club's practice squad on cutdown day, own cuts first.
    ///
    /// ORDERING (load-bearing): this runs AFTER `WeekAdvancer.startNewSeason`,
    /// i.e. after `refillAIRosters` has topped every active roster back up to
    /// 53 out of the free-agent pool. Run before it and the refill — which
    /// filters on `teamID == nil` and sorts by the same keep-score used here —
    /// would strip the best man off every squad the moment it was assembled.
    ///
    /// ## Allocation: one man per club per round (task #144)
    ///
    /// This used to run each club's whole 16-man fill before moving to the next.
    /// Out of ONE shared market that is a first-come-take-all draw, and the
    /// shuffle only moved WHO it favoured: measured over an 8-season smoke the
    /// league ran `avg=6.3 min=4 max=16` — a handful of clubs at the ceiling, a
    /// tail sitting on the invented-body floor, every season. A squad is not a
    /// prize for winning a coin toss, so the market is now dealt round-robin:
    /// each club takes its single best available man, then the next club takes
    /// its own, until nobody can add. Same men, same ranking, same total; the
    /// spread across 32 clubs is what changes.
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

        // The service ledger the eligibility rule is written in. One fetch for
        // the whole cutdown — see ``accruedSeasonsByPlayer``.
        let accruedByID = accruedSeasonsByPlayer(career: career, modelContext: modelContext)
        func accrued(_ player: Player) -> Int { accruedByID[player.id] ?? 0 }

        // One shared market. `taken` keeps the 32 clubs from all signing the
        // same man. NOTE the absence of an OVR clause here: the ceiling is a
        // property of the SEAT (unrestricted seats take sub-70 men, the six
        // veteran slots take anybody no 53 would keep), so it belongs in
        // `isSquadEligible` and nowhere else. Filtering it in at this level was
        // what hid the league's 176-207 unsigned journeymen from the veteran
        // slots that exist for exactly them.
        var taken = Set<UUID>()
        let pool = allPlayers.filter {
            $0.teamID == nil && !$0.isRetired && !$0.isOnPracticeSquad
        }
        summary.poolSize = pool.count
        summary.poolYoung = pool.filter { !needsVeteranSlot($0, accruedSeasons: accrued($0)) }.count
        summary.poolCut = pool.filter { $0.cutByTeamID != nil }.count

        // The user's own answer to "who do we keep developing": the players he
        // ticked as practice-squad-eligible while working the 90 → 53 cut flow
        // (`RosterCutView` writes `RosterCut.practiceSquadEligible`). Until this
        // existed that tick did nothing at all.
        let keeperIDs = userFlaggedKeepers(career: career, modelContext: modelContext)

        // Fetch order is not a signing order — see `refillAIStaffVacancies` for
        // the same argument. With the round-robin below the shuffle no longer
        // decides who gets a squad at all, only who gets first pick inside each
        // round, but a coin toss is still the honest tie-break.
        var states = teams.shuffled().map {
            ClubFill(team: $0, roster: activeRoster(of: $0.id, in: allPlayers))
        }

        /// Books one signing against club `index`.
        func add(_ player: Player, at index: Int, keeper: Bool = false) {
            let teamID = states[index].team.id
            stash(player, on: teamID)
            taken.insert(player.id)
            states[index].squad.append(player)
            states[index].countByPosition[player.position, default: 0] += 1
            if needsVeteranSlot(player, accruedSeasons: accrued(player)) {
                states[index].veteransUsed += 1
            }
            if keeper || player.cutByTeamID == teamID {
                summary.fromOwnCuts += 1
            } else {
                summary.fromStreetFreeAgents += 1
            }
        }

        // Pass 0: the user's flagged keepers, ahead of everything.
        //
        // These are the only squad signings that can come off an ACTIVE roster,
        // which is the whole point — the user marked them while deciding who to
        // release, so stashing one IS the release, and his cap charge has to
        // come back off the ledger with him. The OVR gate in `isSquadEligible`
        // is deliberately not applied: the user is allowed to stash a better
        // player than the AI would, at the cost of the roster spot he just gave
        // up.
        if let userIndex = states.firstIndex(where: { $0.team.id == career.teamID }),
           !keeperIDs.isEmpty {
            let team = states[userIndex].team
            let keepers = allPlayers
                .filter { keeperIDs.contains($0.id) && !$0.isRetired && !$0.isOnPracticeSquad }
                .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
            for keeper in keepers where states[userIndex].squad.count < squadSize {
                guard !taken.contains(keeper.id) else { continue }
                let positionCap = keeper.position == .QB ? maxQuarterbacks : maxPerPosition
                guard (states[userIndex].countByPosition[keeper.position] ?? 0) < positionCap else { continue }
                if needsVeteranSlot(keeper, accruedSeasons: accrued(keeper)),
                   states[userIndex].veteransUsed >= veteranSlots { continue }
                if keeper.teamID == team.id, career.capMode != .sandbox {
                    team.currentCapUsage -= keeper.annualSalary
                }
                add(keeper, at: userIndex, keeper: true)
            }
        }

        // Passes 1-16: the round-robin. Each club takes ONE man per round —
        // its own best available, ranked own-cuts-first and then by whether he
        // covers a thin position group — and the round ends when every club has
        // had its turn. Runs until a whole round signs nobody.
        var candidates = pool
        for _ in 0..<squadSize {
            var signedThisRound = 0
            for index in states.indices where !states[index].isDone {
                guard states[index].squad.count < squadSize else {
                    states[index].isDone = true
                    continue
                }
                let teamID = states[index].team.id
                let isUserClub = teamID == career.teamID
                let veteransUsed = states[index].veteransUsed
                let counts = states[index].countByPosition
                // Recomputed each turn: the man signed last round changed what
                // this club is now thinnest at.
                let needs = Set(DraftEngine.topTeamNeeds(
                    roster: states[index].roster + states[index].squad, limit: 6
                ))

                var best: Player?
                var bestRank = -Double.greatestFiniteMagnitude
                for player in candidates {
                    guard !taken.contains(player.id) else { continue }
                    // A man the user flagged as a keeper is spoken for; an AI
                    // club drawn earlier in the round must not lift him out of
                    // the shared market before Pass 0 has run.
                    guard isUserClub || !keeperIDs.contains(player.id) else { continue }
                    guard isSquadEligible(
                        player, usedVeteranSlots: veteransUsed, accruedSeasons: accrued(player)
                    ) else { continue }
                    let cap = player.position == .QB ? maxQuarterbacks : maxPerPosition
                    guard (counts[player.position] ?? 0) < cap else { continue }

                    // Own cuts first — the club knows these bodies, and every
                    // real squad is built out of the men it just released.
                    // `cutByTeamID` is stamped by the user's cut flow
                    // (`WaiverWireEngine`) and by the AI cutdown
                    // (`WeekAdvancer.trimAIRosters`).
                    var score = RosterValue.keepScore(player)
                    if player.cutByTeamID == teamID { score += 1_000 }
                    if needs.contains(player.position) { score += 500 }
                    if score > bestRank { bestRank = score; best = player }
                }

                guard let pick = best else {
                    states[index].isDone = true
                    continue
                }
                add(pick, at: index)
                signedThisRound += 1
            }
            candidates.removeAll { taken.contains($0.id) }
            if signedThisRound == 0 { break }
        }

        // Last pass: the market ran dry — street free agents report for a
        // tryout, the same fallback `refillAIRosters` uses when the pool has
        // nothing left. Bounded at ``squadGenerationFloor``: a short squad is
        // the honest reading of an empty market, and an unbounded one here was
        // the league's largest single source of invented population (see the
        // constant).
        for index in states.indices {
            let team = states[index].team
            while states[index].squad.count < squadGenerationFloor {
                let needs = DraftEngine.topTeamNeeds(
                    roster: states[index].roster + states[index].squad, limit: 3
                )
                let counts = states[index].countByPosition
                let position = needs.first(where: {
                    ($0 == .QB ? maxQuarterbacks : maxPerPosition) > (counts[$0] ?? 0)
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
                states[index].squad.append(generated)
                states[index].countByPosition[position, default: 0] += 1
                summary.generated += 1
            }

            if !states[index].squad.isEmpty { summary.clubsFilled += 1 }
            summary.squadDepths.append(states[index].squad.count)
            summary.veteranSlotsUsed += states[index].veteransUsed
        }

        print(summary.diagnosticLine)
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
