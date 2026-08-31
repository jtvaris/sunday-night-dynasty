import Foundation
import SwiftData

// MARK: - CampRosterEngine

/// #205a — the camp-invite wave: the 87-man offseason roster, assembled from
/// men the league already produced (`OFFSEASON_ROSTER_PLAN.md` §3.3).
///
/// ## What this fixes
///
/// The 90 → 53 ladder shipped with its rungs in place — `CutDay.rung(dueIn:)`
/// puts "Cut to 75" on the `.trainingCamp` exit and "Cut to 65" on the
/// `.preseason` exit, and `WeekAdvancer.userRosterLimitViolation` gates both —
/// but nothing ever put a camp's worth of men in a camp. QA measured the roster
/// settling at
/// **64** (53 survivors + the draft class + the UDFA market), so both upper
/// rungs were satisfied on arrival and auto-skipped: two required tasks that
/// could never be due, and a cutdown story that started at the last chapter.
/// This pass is the missing half — the camp itself.
///
/// ## Three rules, and the reason for each
///
/// 1. **Target 87, ceiling 90.** `TradeValueEngine.offseasonRosterCeiling` is
///    already 90 and its doc comment already claims the league carries 80-90
///    between the draft and cutdown day; this is the pass that finally makes
///    that true. Filling *to* the ceiling would make every offseason
///    acquisition illegal on the body count and kill the AI trade market in
///    exactly the windows it is supposed to be open, so the target keeps a
///    little headroom (§1, risk B9) — see ``campRosterTarget`` for why the
///    headroom shrank from ten slots to three.
///
/// 2. **NEVER generate a player.** There is no generation path in this file at
///    all — not a bounded one, not a fallback. `PracticeSquadEngine`'s
///    ``PracticeSquadEngine/squadGenerationFloor`` records what the unbounded
///    version of this idea cost when `fillSquads` last had one: **417 / 250 /
///    212 / 244 minted players a season**, the inflow half of task #99's shadow
///    pool. The arithmetic here is worse — 32 clubs × ~23 open camp slots is
///    ~730 bodies a season — so the door is not narrowed, it is absent. A club
///    that cannot find bodies carries fewer men; the target is a **ceiling, not
///    a quota**, and a short camp is the honest reading of an empty market.
///
/// 3. **The cycle is closed.** Every camp body comes out of the unsigned pool
///    at the `.otas` exit and goes back into it at cutdown, four phases later
///    (``settleCampBodies`` keeps only the survivors). Net minting is zero by
///    construction: the pool stops being a stagnant reservoir and becomes
///    inventory. `poolBefore` / `poolAfter` in ``FillSummary/diagnosticLine``
///    are what §6/B4 gates that claim on.
///
/// ## Cap treatment — camp bodies are cap-exempt (§3.1)
///
/// A man carried above the 53 during the offseason is a **camp body**
/// (`RosterStatus.campBody`). His salary is written on his row and is **never
/// added to `Team.currentCapUsage`** while he is one. The flag clears — and the
/// salary is charged — the moment he survives to the 53, in
/// ``settleCampBodies`` at the `.rosterCuts → .regularSeason` boundary.
///
/// That IS the top-51 rule, in the ledger shape this codebase has. The real
/// rule excludes the bottom ~38 minimum deals during the offseason; camp bodies
/// are *by construction* exactly that population (every one of them signs at
/// `ContractEngine.veteranMinimum(cap:)`). A literal top-51 rule is a statement
/// about a sorted set, and `currentCapUsage` is an incrementally maintained
/// counter rebuilt from the roster once a year at
/// `FreeAgencyEngine.executeNewLeagueYear` — expressing "the 51 largest" there
/// would mean recomputing the whole sum at every one of its dozen `+=` sites.
///
/// **The trap the precedent warns about.** A practice-squad man is cap-exempt
/// and safe because `teamID == nil` keeps every refund path away from him. A
/// camp body has `teamID != nil` — he must dress in preseason, appear on the
/// depth chart and be visible to `GameSimulator` — so the refund paths *would*
/// fire for him and walk each club's ledger down by ~$12M every camp. Four
/// guards prevent that, all of them in `Engine/Contract`, all of them naming
/// this section:
///
/// * `CapManagementEngine.applyRelease` — the one release door: no credit, no
///   dead money, and the status is cleared on the way out.
/// * `TradeEngine.applyPlayerMove` — the buyer is charged, the seller is not
///   credited.
/// * `ContractEngine.signPlayer` — a new deal nets against 0, not against a
///   salary the club was never carrying.
/// * `FreeAgencyEngine.executeNewLeagueYear` — the true-up skips camp bodies,
///   defensively: the flag is always cleared before a rollover, and the true-up
///   is the ledger's ground truth, so it must not be able to disagree.
@MainActor
enum CampRosterEngine {

    // MARK: - League rules

    /// Men a club carries out of this pass. **A ceiling, not a quota** — see
    /// rule 2 in the type doc.
    ///
    /// Not 90: `TradeValueEngine.offseasonRosterCeiling` is 90 and the offseason
    /// trade market vetoes any deal that would breach it, so filling to the
    /// ceiling would close the market for the four phases §5 of the trade plan
    /// expects business in. The headroom is the difference.
    ///
    /// **80 → 87 (#199).** The first shipped number left the headroom at ten
    /// slots, and the review found the cost of that generosity on the only rung
    /// that is *named* after a number: `CutDay.cut90To75` asked for five cuts
    /// instead of fifteen, so the loudest chapter of the cutdown story — the
    /// first one — read as a formality. Three slots is enough headroom for the
    /// market that actually needs it: a 1-for-1 swap is body-count neutral, a
    /// 2-for-1 acquisition needs one slot, and in the two windows where the AI
    /// market is busiest the AI clubs sit **well below** the target anyway,
    /// because PHASE A serves the user's camp out of the same inventory first.
    /// It is also what a real August looks like — a club at the limit cuts
    /// before it signs, which is a decision, not a veto.
    static let campRosterTarget = 87

    /// The hard ceiling this pass may never breach — shared with the trade
    /// market so the two cannot disagree about what a legal offseason roster is.
    static var rosterCeiling: Int { TradeValueEngine.offseasonRosterCeiling }

    /// Years on a camp invite.
    ///
    /// One. A camp deal is a tryout, and a one-year minimum contract with no
    /// signing bonus is what makes a camp cut cost **zero dead money**:
    /// `RosterCutEvaluator.deadCap` is `0.15 × salary × years`, and
    /// `applyRelease`'s camp-body guard books neither the relief nor the charge,
    /// so the ledger does not move in either direction when the man is cut.
    static let campContractYears = 1

    /// The shape of an 87-man camp: the most bodies a club may carry at each
    /// position.
    ///
    /// **Why a table and not a need model.** The obvious authority here is
    /// `DraftEngine.teamNeedDeficits`, which the UDFA market reads. It cannot be
    /// used for this pass: its evidence half raises a "need" when a position
    /// group *averages under 70*, and a camp body's whole job is to be a
    /// sub-70 body. Signing one would deepen the very deficit that selected the
    /// position, so a needs-driven camp fill converges on twelve receivers and
    /// no linebackers. `topTeamNeeds` is worse — on a full roster it returns the
    /// same {QB, DE, CB, WR, LT} quintet for all 32 clubs (see its own doc
    /// comment), which would have every club in the league sign six
    /// quarterbacks.
    ///
    /// So the shape is stated, once, as the thing it actually is: what a real
    /// 90-man August roster looks like. It is `LeagueGenerator.rosterBlueprint`
    /// (the 53) opened up where a camp actually works — receivers, corners, the
    /// two lines — and held nearly shut at the three positions where a camp body
    /// is pure waste (QB, K, P). The sum is 98, comfortably above
    /// ``campRosterTarget`` (87) so no club is shape-locked short of its target.
    /// It is deliberately ABOVE ``rosterCeiling`` (90): the shape is a
    /// per-position cap, not a roster size — the fill loop stops at the target
    /// and the ceiling regardless — and a shape that only just cleared the
    /// target is what left clubs one man short before #199.
    ///
    /// **94 → 98 (positions-st).** The long snapper and the holder are roster
    /// Positions now, so a camp that could not carry a second one had no way to
    /// bring in competition for either job. Two apiece, exactly like the kicker
    /// and the punter, whose room this is.
    ///
    /// **86 → 94 (#199).** The shape is a per-position ceiling, so the *sum*
    /// minus a club's existing roster is the reachable headroom, and the old sum
    /// of 86 left only six slots above the old target of 80 — raise the target to
    /// 87 against an 86-man shape and every club is shape-locked one man short
    /// of the number before the market is even consulted. The eight extra slots
    /// go where a camp body is actually plausible (WR, TE, CB, the two interior
    /// guard spots, DE, DT, OLB); QB, K, P and the pivot are untouched, which is
    /// the whole point of having a shape rather than a body count.
    static let campShape: [Position: Int] = [
        .QB: 4, .RB: 5, .FB: 2, .WR: 11, .TE: 6,
        .LT: 3, .LG: 4, .C: 3, .RG: 4, .RT: 3,
        .DE: 8, .DT: 7, .OLB: 7, .MLB: 5,
        .CB: 10, .FS: 4, .SS: 4,
        .K: 2, .P: 2, .LS: 2, .H: 2
    ]

    /// What a camp invite pays: the league minimum at this club's cap, read from
    /// the one place the floor is defined.
    static func campSalary(for team: Team) -> Int {
        ContractEngine.veteranMinimum(cap: team.salaryCap)
    }

    // MARK: - The pool

    /// The men a camp invite may be offered to: unsigned, unretired, not stashed
    /// on anybody's practice squad.
    ///
    /// Injured men are deliberately **included**. `WeekAdvancer.refillAIRosters`
    /// filters them out because it is assembling a roster that has to play next
    /// Sunday; a camp invite is a look, and the real league fills its PUP list
    /// with exactly these men. Excluding them would also make the pool's largest
    /// permanent residue — men nobody signs *because* they are hurt, who
    /// therefore never heal on a training staff — structurally unreachable.
    ///
    /// Squads are dissolved at the new league year
    /// (`FreeAgencyEngine.executeNewLeagueYear` → `dissolveSquads`), months
    /// before this pass runs, so the squad clause is belt and braces rather than
    /// a live filter.
    static func invitePool(_ allPlayers: [Player]) -> [Player] {
        allPlayers.filter {
            $0.teamID == nil
                && !$0.isRetired
                && !$0.isOnPracticeSquad
                && $0.practiceSquadTeamID == nil
        }
    }

    // MARK: - Summaries

    /// What one camp fill did.
    ///
    /// Three counts, and the distinction between them is the whole balance
    /// argument:
    ///
    /// * `fromPool` — men who already had a row and a face. Free, and returned
    ///   to the pool at cutdown, so the cycle closes at zero.
    /// * `fromUndrafted` — this year's undrafted remainder, minted at the moment
    ///   of the invite. Bounded by the draft class (never more than the ~50-90
    ///   men the UDFA market left), and they were going to be **deleted unplayed**
    ///   at `purgeStaleSeasonData` a season later, so this is a man the league
    ///   already produced getting a career rather than a man invented to fill a
    ///   number.
    /// * `generated` — `LeagueGenerator.generatePlayer`, the #99 door. Structurally
    ///   zero: this engine does not import that path. §6/B4 asserts it.
    struct FillSummary {
        var clubsFilled = 0
        var fromPool = 0
        var fromUndrafted = 0
        var generated = 0
        var poolBefore = 0
        var poolAfter = 0
        var undraftedBefore = 0
        var userSignings = 0
        var userRosterAfter = 0
        var smallestRoster = 0
        var largestRoster = 0

        var signings: Int { fromPool + fromUndrafted }

        /// How many men short of ``campRosterTarget`` the user's camp finished.
        ///
        /// **The G2 number.** Everything else on the diagnostic line describes
        /// the league; this one describes the only camp that gets played, and it
        /// is the one that decides whether the 75 / 65 rungs are real work or
        /// rows that auto-satisfy. Non-zero means the inventory ran dry before
        /// the user's club filled — the pass will not invent a body to hide it
        /// (rule 2), so it says so instead.
        var userShortfall: Int { max(0, campRosterTarget - userRosterAfter) }

        /// The B4 gate line: `generated == 0` (hard), `userShort=0` (the G2
        /// gate), and `poolAfter` back within ±15 % of `poolBefore` across
        /// seasons once the cycle is closed by ``settleCampBodies``.
        func diagnosticLine(season: Int) -> String {
            "SMOKE: diag campRoster season=\(season) clubs=\(clubsFilled) "
                + "filled=\(signings) fromPool=\(fromPool) fromUndrafted=\(fromUndrafted)"
                + "/\(undraftedBefore) generated=\(generated) "
                + "poolBefore=\(poolBefore) poolAfter=\(poolAfter) "
                + "rosters=\(smallestRoster)-\(largestRoster) "
                + "user=\(userRosterAfter)(+\(userSignings)) userShort=\(userShortfall)"
        }
    }

    /// What cutdown day did with the men who were still camp bodies.
    struct SettleSummary {
        var survivors = 0
        var capCharged = 0
    }

    // MARK: - 1. Fill

    /// Assembles every club's camp roster at the `.otas` exit, after the UDFA
    /// market has settled.
    ///
    /// **All 32 clubs, the user's included.** A league-wide pass that skips the
    /// user's club is the defect audit A opened with (the deleted UDFA bulk
    /// block did exactly that and then mailed him about the market he had been
    /// left out of), and it is also the only way the 75 and 65 rungs can be real
    /// for him: a club that walks into camp at 64 has already satisfied both.
    ///
    /// **The user's club first, then round-robin over a shuffled club order,
    /// one man per club per pass.**
    ///
    /// The round-robin half is unchanged and is there for the reason it always
    /// was: club-at-a-time is defect #10 (`WeekAdvancer` :3757) and the #144
    /// finding in `fillSquads`, both of which were "the first few clubs emptied
    /// the market". The shuffle decides who picks first inside a round, never
    /// who gets a camp at all.
    ///
    /// The user's club going first is #208 G2, and it is an inventory argument,
    /// not a privilege: the league's whole camp inventory at this moment is
    /// roughly a hundred men, so one-per-club round-robin gives all 32 clubs
    /// three apiece and nobody a camp. See the PHASE A comment in the body.
    ///
    /// **Two sources, in strict order.** A club's turn looks for a man at the
    /// position it is thinnest at: first in the unsigned pool, and only if that
    /// position is empty there, among the undrafted men the UDFA market finished
    /// with (``UDFAMarketEngine/campInviteCandidates(career:prospects:)``).
    ///
    /// The order is the balance rule. A pool man is free — his row and his face
    /// already exist and he goes back to the pool at cutdown, so the cycle
    /// closes at zero. An undrafted man has to be minted and claims a face out
    /// of a 3 584-id catalog that `MultiSeasonSmokeTest.auditFaces` already
    /// reports running to `free=0`, so he is drawn only where a camp would
    /// otherwise not exist. In an established league (#99's ~900-man pool) that
    /// is almost never; in the league's first two offseasons — where the pool
    /// has not accumulated yet and QA measured clubs settling at **64** — it is
    /// what makes ``campRosterTarget`` reachable at all. `FillSummary` reports
    /// the split, and it
    /// is expected to fall towards `fromPool` as a career ages.
    ///
    /// Face duplication is accepted, not worked around: `FaceLibrary` reports
    /// `POOL FULL — reuse unavoidable` and hands out a repeat (or `nil`, which
    /// renders the placeholder) rather than trapping, which is the documented
    /// capacity behaviour. The catalog is not grown for camp bodies — a man who
    /// is cut in August was never going to be looked at twice.
    ///
    /// Idempotent through `Career.campFillSeason`, a PERSISTED stamp in the same
    /// shape as `Career.lastRolloverSeason` and `Career.lastBulkMarketSeason`.
    /// A re-entered phase, or a cold launch in the middle of one, cannot fill a
    /// camp twice.
    @discardableResult
    static func fillCampRosters(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        prospects: [CollegeProspect],
        allCoaches: [Coach],
        modelContext: ModelContext
    ) -> FillSummary {
        var summary = FillSummary()
        guard career.campFillSeason < career.currentSeason else { return summary }
        career.campFillSeason = career.currentSeason

        // The pool, bucketed by position and ranked ONCE.
        //
        // Ranking per turn instead would be ~500 signings × up to 19 positions ×
        // a ~900-man pool of `RosterValue.keepScore` calls, and `keepScore` reads
        // `Player.overall`, which is computed from three attribute blocks on
        // every access. That is the shape of offseason stall this wave's risk R5
        // is about; one sort of each bucket up front costs ~900 evaluations for
        // the whole league.
        let pool = invitePool(allPlayers)
        summary.poolBefore = pool.count
        var poolByPosition: [Position: [Player]] = [:]
        for player in pool { poolByPosition[player.position, default: []].append(player) }
        for position in poolByPosition.keys {
            let ranked = poolByPosition[position]?
                .map { (player: $0, score: RosterValue.keepScore($0)) }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.player.id.uuidString < rhs.player.id.uuidString
                }
                .map(\.player)
            poolByPosition[position] = ranked
        }

        // The second source, ordered by true value: nobody user-facing reads
        // this list (see the accessor's doc), and a camp that took the worst men
        // in the class first would be a strange league.
        var undrafted = UDFAMarketEngine.campInviteCandidates(career: career, prospects: prospects)
        summary.undraftedBefore = undrafted.count

        var coachesByTeam: [UUID: [Coach]] = [:]
        for coach in allCoaches {
            guard let teamID = coach.teamID else { continue }
            coachesByTeam[teamID, default: []].append(coach)
        }

        var rosterByTeam: [UUID: [Player]] = [:]
        for player in allPlayers where !player.isRetired {
            guard let teamID = player.teamID else { continue }
            rosterByTeam[teamID, default: []].append(player)
        }

        /// One club's state for the duration of the pass.
        struct ClubFill {
            let team: Team
            var count: Int
            var countByPosition: [Position: Int]
            var signings = 0
            var isDone = false
        }

        var states = teams.shuffled().map { team -> ClubFill in
            let roster = rosterByTeam[team.id] ?? []
            var counts: [Position: Int] = [:]
            for player in roster { counts[player.position, default: 0] += 1 }
            return ClubFill(team: team, count: roster.count, countByPosition: counts)
        }

        /// One club's turn: sign the best available man at the position it is
        /// thinnest at, or mark it done. Returns whether anybody was signed.
        ///
        /// Extracted so the two allocation phases below run the SAME turn — the
        /// user's club is not given different rules, only an earlier turn.
        func takeTurn(_ index: Int) -> Bool {
            guard !states[index].isDone else { return false }
            guard states[index].count < campRosterTarget,
                  states[index].count < rosterCeiling else {
                states[index].isDone = true
                return false
            }
            let team = states[index].team
            let counts = states[index].countByPosition

            // The position this club is thinnest at RELATIVE TO THE CAMP
            // SHAPE, recomputed every turn — the man signed last round
            // changed the answer. Room, not a need score: see ``campShape``
            // for why a need model cannot be used here.
            let wanted = campShape
                .map { (position: $0.key, room: $0.value - (counts[$0.key] ?? 0)) }
                .filter { $0.room > 0 }
                .sorted { lhs, rhs in
                    if lhs.room != rhs.room { return lhs.room > rhs.room }
                    return lhs.position.rawValue < rhs.position.rawValue
                }
            guard !wanted.isEmpty else {
                states[index].isDone = true
                return false
            }

            // Position by position, pool first. Walking the positions in
            // room order (rather than taking the best pool man anywhere)
            // keeps the SHAPE honest: a club whose secondary is empty signs
            // an undrafted corner rather than the pool's fourth tight end.
            var signed: Player?
            for entry in wanted {
                if let best = takeBestPoolMan(
                    at: entry.position, from: &poolByPosition, teamID: team.id
                ) {
                    invite(best, to: team, career: career)
                    signed = best
                    summary.fromPool += 1
                    break
                }
                if let rookieIndex = undrafted.firstIndex(where: { $0.position == entry.position }) {
                    let prospect = undrafted.remove(at: rookieIndex)
                    let minted = inviteUndrafted(
                        prospect,
                        to: team,
                        coaches: coachesByTeam[team.id] ?? [],
                        career: career,
                        modelContext: modelContext
                    )
                    signed = minted
                    summary.fromUndrafted += 1
                    break
                }
            }

            guard let signing = signed else {
                // Neither source has a man at any position this club has
                // room for. Not a failure, and not a reason to invent
                // anybody — see rule 2. The club carries fewer.
                states[index].isDone = true
                return false
            }

            states[index].count += 1
            states[index].countByPosition[signing.position, default: 0] += 1
            states[index].signings += 1
            if team.id == career.teamID { summary.userSignings += 1 }
            return true
        }

        // PHASE A (#208 G2) — the user's club fills to the target FIRST, out of
        // the same inventory and under the same turn.
        //
        // Round-robin alone is a fair way to deal a market that is big enough
        // for 32 camps, and this one is not. The whole league's inventory at
        // this moment is the unsigned pool plus the undrafted remainder — QA
        // measured it at roughly a hundred men — so a strict one-per-club round
        // robin hands every club exactly three: 32 × 3 ≈ the entire warehouse,
        // the user included. That is the number QA reported (a roster peaking at
        // 61) and it is why both upper rungs of the ladder were satisfied on
        // arrival. Fair shares of nothing is still nothing.
        //
        // The user's camp is the only camp in the league that is *played* — it
        // is the one with a cut ladder gated on it (`userRosterLimitViolation`),
        // the one whose battles resolve on screen and the one whose preseason
        // snaps are watched. So it is filled first, and the AI clubs deal what
        // is left between them round-robin as before. No club is skipped, which
        // was audit A's defect; the user is simply served before the 31 clubs
        // whose camp rosters are trimmed back to 53 by `trimAIRosters` without
        // anybody ever looking at them.
        if let userIndex = states.firstIndex(where: { $0.team.id == career.teamID }) {
            // Bounded by the target: `takeTurn` marks the club done the moment
            // it is full or the market is dry, so this cannot spin.
            for _ in 0..<campRosterTarget {
                if !takeTurn(userIndex) { break }
            }
        }

        // PHASE B — passes 1…target: each remaining club takes ONE man per
        // round. The round ends when every club has had its turn; the whole pass
        // ends when a full round signs nobody (an empty market, or every club at
        // its target).
        for _ in 0..<campRosterTarget {
            var signedThisRound = 0
            for index in states.indices where !states[index].isDone {
                if takeTurn(index) { signedThisRound += 1 }
            }
            if signedThisRound == 0 { break }
        }

        summary.poolAfter = summary.poolBefore - summary.fromPool
        summary.clubsFilled = states.filter { $0.signings > 0 }.count
        summary.smallestRoster = states.map(\.count).min() ?? 0
        summary.largestRoster = states.map(\.count).max() ?? 0
        summary.userRosterAfter = states.first { $0.team.id == career.teamID }?.count ?? 0

        try? modelContext.save()
        print(summary.diagnosticLine(season: career.currentSeason))
        return summary
    }

    /// How deep into a position's ranked bucket a club will reach for a man it
    /// cut itself.
    ///
    /// Own cuts first is real — every August camp list is half last year's
    /// releases, and `cutByTeamID` is stamped by the one release door — but it
    /// is a tie-break, not a mandate: a club should not sign the 41st-best
    /// available corner because he used to be theirs. Six is "look down the top
    /// of the board for a familiar name", which is what a personnel department
    /// actually does.
    private static let ownCutLookahead = 6

    /// Takes the best unsigned man at one position out of the ranked pool, or
    /// `nil` if the pool has nobody there.
    ///
    /// Removing rather than marking is what keeps the pass linear: the bucket is
    /// pre-ranked by `RosterValue.keepScore` — the key the AI cutdown, the
    /// practice-squad fill and the season-start refill all agree on, so a camp
    /// invite is not the one pass in the game that prefers a different kind of
    /// player from the one August will keep — and a turn is a constant-time look
    /// at its front.
    private static func takeBestPoolMan(
        at position: Position,
        from poolByPosition: inout [Position: [Player]],
        teamID: UUID
    ) -> Player? {
        guard var bucket = poolByPosition[position], !bucket.isEmpty else { return nil }
        var chosen = 0
        for index in 0..<min(bucket.count, ownCutLookahead)
        where bucket[index].cutByTeamID == teamID {
            chosen = index
            break
        }
        let man = bucket.remove(at: chosen)
        poolByPosition[position] = bucket
        return man
    }

    /// Mints one undrafted man as a camp body.
    ///
    /// Through `DraftEngine.convertUDFAToPlayer` — the same door the draft-night
    /// panel and the UDFA market use, so there is exactly one definition in the
    /// game of what an undrafted prospect becomes — with the contract overwritten
    /// to a camp deal afterwards, exactly as `UDFAMarketEngine.sign` overwrites
    /// it with the deal a contested man was bid. The difference from a market
    /// signing is the one that matters: **no cap charge**, and
    /// `rosterStatus = .campBody`.
    ///
    /// `isDeclaringForDraft` is cleared here as well as by `closeMarket`
    /// (defect D1): the flag is the pool's membership predicate and every path
    /// that takes a man out of the pool must clear it, whether or not another
    /// path already did.
    private static func inviteUndrafted(
        _ prospect: CollegeProspect,
        to team: Team,
        coaches: [Coach],
        career: Career,
        modelContext: ModelContext
    ) -> Player {
        let player = DraftEngine.convertUDFAToPlayer(
            prospect: prospect,
            teamID: team.id,
            salaryCap: team.salaryCap
        )
        DraftEngine.initializeRookieFamiliarity(
            player: player,
            prospect: prospect,
            coaches: coaches,
            isUndrafted: true
        )
        prospect.isDeclaringForDraft = false
        modelContext.insert(player)
        invite(player, to: team, career: career)
        UDFAMarketEngine.consumeCampInvite(career: career, prospectID: prospect.id)
        return player
    }

    /// Writes the camp invite onto the man. **No cap charge** — see §3.1 in the
    /// type doc.
    ///
    /// Every field that could survive from a previous deal and become a charge
    /// on this club is cleared here: a pool player normally arrives with them
    /// already zeroed by `applyRelease`, but a man whose contract simply expired
    /// at the rollover did not go through that door, and a restructure receipt
    /// riding into camp would book dead money against a club that never wrote
    /// the bonus.
    private static func invite(_ player: Player, to team: Team, career: Career) {
        player.teamID = team.id
        player.rosterStatus = .campBody
        player.contractYearsRemaining = campContractYears
        player.annualSalary = campSalary(for: team)
        player.proratedFullBaseSalary = 0
        player.restructureReliefK = 0
        player.restructureProrationK = 0
        player.restructureCarryYears = 0
        player.isFranchiseTagged = false
        player.franchiseTagSeason = 0
        player.isHoldingOut = false
        player.trainingFocusArea = nil
        player.trainingPosition = nil
        player.careerID = career.id          // invariant 6
        // NO `team.currentCapUsage += …`. That is the whole mechanism.
    }

    // MARK: - 2. Settle

    /// Cutdown day: the men who survived to the 53 stop being camp bodies and
    /// go on the club's cap sheet.
    ///
    /// Called at the `.rosterCuts → .regularSeason` boundary, after
    /// `trimAIRosters` and the user's own cut flow have taken every club to 53,
    /// and BEFORE `startNewSeason` → `refillAIRosters`, which reads
    /// `availableCap` when it signs. Whoever is still flagged at this point made
    /// the team, so the charge the exemption deferred falls due in full.
    ///
    /// Idempotent: it keys on the flag and clears it, so a second call finds
    /// nobody and charges nothing.
    @discardableResult
    static func settleCampBodies(
        career: Career,
        teams: [Team],
        allPlayers: [Player]
    ) -> SettleSummary {
        var summary = SettleSummary()
        guard career.capMode != .sandbox else {
            // Sandbox keeps no ledger at all (`tradeCapSplit`'s early return);
            // the flag still has to clear or the man stays a camp body forever.
            for player in allPlayers where player.rosterStatus == .campBody {
                player.rosterStatus = .active
                summary.survivors += 1
            }
            return summary
        }

        var teamsByID: [UUID: Team] = [:]
        for team in teams { teamsByID[team.id] = team }

        for player in allPlayers where player.rosterStatus == .campBody {
            player.rosterStatus = .active
            guard let teamID = player.teamID, let team = teamsByID[teamID] else {
                // Released during camp and the release door missed the reset —
                // clearing the flag is still correct, and there is nobody to
                // charge.
                continue
            }
            team.currentCapUsage += player.annualSalary
            summary.survivors += 1
            summary.capCharged += player.annualSalary
        }
        return summary
    }

    /// A camp body leaving his camp — by release, by trade, or by signing a real
    /// deal — stops being one.
    ///
    /// The one-line half of every guard listed in the type doc, published here
    /// so the rule has a single spelling. **Leaving it out is a ledger leak, not
    /// a cosmetic miss**: a man who kept the flag after his release would be
    /// exempted from the cap credit on his *next*, fully charged release, and
    /// the club's usage would ratchet upward by his salary every time.
    static func clearCampBodyStatus(_ player: Player) {
        if player.rosterStatus == .campBody { player.rosterStatus = .active }
    }

    /// Whether this man is currently carried as a camp body — the predicate the
    /// four `Engine/Contract` guards read.
    static func isCampBody(_ player: Player) -> Bool {
        player.rosterStatus == .campBody
    }
}
