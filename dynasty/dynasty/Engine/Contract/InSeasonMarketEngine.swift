import Foundation

// MARK: - InSeasonMarketEngine

/// **The street, in November.** (D4-A)
///
/// ## The hole this fills
///
/// `docs/AI_SEASON_LIFECYCLE_ANALYSIS.md` §1.1.2 verified it by reading
/// `advanceRegularSeasonWeek` end to end: there is not one `FreeAgencyEngine`
/// call anywhere in the regular season. Every AI signing entry point
/// (`simulateAIFreeAgency`, `simulateRemainingFA`, `resignAIOwnCore`,
/// `signFreeAgentAI`) is reachable only from the `.freeAgency` phase or a user
/// screen. Street free agents signed in-season, per club per season: **0**,
/// against a real league where every club signs veterans off the street during
/// the year, most weeks. A club that lost three corners in week 5 signed nobody,
/// and its ability to respond to a hole was concentrated entirely in one March
/// afternoon — whatever it did not fix then, it carried for twelve months.
///
/// That single fact is most of why an AI club made **≈1.4 roster moves a
/// season** against a real club's hundred-plus.
///
/// ## The model
///
/// Need-gated, not budget-gated. A club signs off the street when
/// `PracticeSquadEngine.shorthandedPositions` says a position room is below its
/// ideal count **on the available roster** — the same availability read the
/// poach board and the elevation pass use, so "we need a corner" means one thing
/// in all three markets. The pass runs after both of those, so a club that
/// reaches this door has already looked at its own squad and at everybody
/// else's: the street is the third answer, exactly as it is in the real league.
///
/// ``weeklyLeagueSigningCap`` is a rail, not the mechanism. It exists because
/// the unsigned pool is a shared resource and one pathological week — a
/// league-wide injury cluster, a sandbox roster, an import mid-repair — should
/// not empty it.
///
/// ## Why the ceiling
///
/// ``streetCeilingOverall``: a genuinely good football player is not available
/// in November. Everyone worth a starting job was signed in March; what is left
/// on the wire in week 9 is camp cuts, washouts and men coming back from a year
/// out. Without the ceiling this door would quietly become a second free-agency
/// phase running eighteen times a season, and the March market — which is the
/// one the user plays in — would be picked over by clubs that could simply wait.
enum InSeasonMarketEngine {

    // MARK: - League Rules

    /// Signings the league will make in one week.
    ///
    /// At 8 a full season runs ~144 league-wide, ~4.6 per club — the order a
    /// real transaction wire moves at for genuine street signings, once the
    /// gameday elevations that revert (a concept this game does not have) are
    /// taken out of the real number.
    static let weeklyLeagueSigningCap = 8

    /// Signings one club will make in one week. A club that loses three corners
    /// on Sunday replaces one of them on Tuesday and looks again next week; a
    /// club that rebuilds a position room in an afternoon is a cutdown, not a
    /// season.
    ///
    /// **All thirty-two clubs, not thirty-one.** `runWeeklyPass` counts it in
    /// its own loop and ``userRefusal`` counts it off ``userSigningsThisWeek``,
    /// so the user's street door is rationed by this constant and no other. One
    /// number, read from one place, because the whole point of the rail is that
    /// the pool the other clubs are rationed from cannot be drained by the one
    /// club nobody was counting.
    static let maxSigningsPerClubPerWeek = 1

    /// OVR at which a free agent is not somebody who was still available in
    /// November. Set at `PracticeSquadEngine.startingCalibreOverall + 5`: a
    /// notch above the squad ceiling, because a 53-man emergency does reach
    /// slightly higher than a practice-squad seat, and well below the starter
    /// band.
    static let streetCeilingOverall = PracticeSquadEngine.startingCalibreOverall + 5

    /// Active-roster ceiling. Shared value, restated here for the same reason
    /// `PracticeSquadEngine` restates it: this file must not silently disagree
    /// with the door it signs through.
    static let activeRosterCeiling = PracticeSquadEngine.activeRosterCeiling

    // MARK: - Result

    struct Signing {
        let playerID: UUID
        let playerName: String
        let position: Position
        let overall: Int
        let teamID: UUID
        let teamAbbreviation: String
    }

    // MARK: - Weekly Pass

    /// One regular-season week of street signings across the 31 AI clubs.
    ///
    /// The user is not included, and that asymmetry is honest rather than
    /// deliberate: he has no in-season free-agency screen either, so today the
    /// street is shut for everybody. The audit's verdict on that row is
    /// "**Symmetric, and both are wrong**"; this opens the AI half, which is the
    /// half the frozen league table is made of, and the user's half is a screen
    /// and belongs with the rest of D6.
    @discardableResult
    static func runWeeklyPass(
        career: Career,
        teams: [Team],
        allPlayers: [Player]
    ) -> [Signing] {
        guard career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline else {
            return []
        }

        var pool = streetPool(allPlayers: allPlayers)
        guard !pool.isEmpty else { return [] }

        let capMode = career.capMode
        let leagueYearRemaining = CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )

        var signings: [Signing] = []
        // Shuffled so the same clubs do not get first call on a thin pool every
        // week — the ordering bug `refillAIStaffVacancies` documents, in a
        // market where the supply is genuinely scarce.
        for club in teams.filter({ $0.id != career.teamID }).shuffled() {
            guard signings.count < weeklyLeagueSigningCap else { break }

            let roster = allPlayers.filter { $0.teamID == club.id && !$0.isRetired }
            let needs = Set(PracticeSquadEngine.shorthandedPositions(roster: roster))
            guard !needs.isEmpty else { continue }

            var made = 0
            while made < maxSigningsPerClubPerWeek, signings.count < weeklyLeagueSigningCap {
                guard let index = pool.firstIndex(where: { needs.contains($0.position) }) else { break }
                let target = pool[index]
                guard sign(
                    target,
                    to: club,
                    roster: roster,
                    capMode: capMode,
                    leagueYearRemaining: leagueYearRemaining
                ) else {
                    // He is not the problem — the club is full or broke, and it
                    // will be just as full for the next man. Move to the next
                    // club rather than walking the whole pool.
                    break
                }
                pool.remove(at: index)
                ChurnDiag.record(ChurnDiag.inSeasonFA, target)
                signings.append(Signing(
                    playerID: target.id,
                    playerName: target.fullName,
                    position: target.position,
                    overall: target.overall,
                    teamID: club.id,
                    teamAbbreviation: club.abbreviation
                ))
                made += 1
            }
        }

        return signings
    }

    // MARK: - Pool

    /// The men actually available mid-season, best first.
    ///
    /// `contractYearsRemaining == 0` alongside `teamID == nil` is the shared
    /// invariant that separates a free agent from a practice-squad player, who
    /// also carries a nil `teamID` but IS under contract
    /// (`PracticeSquadEngine`'s header explains the shape). `!isInjured` because
    /// a club filling a hole caused by an injury does not fill it with an
    /// injury.
    static func streetPool(allPlayers: [Player]) -> [Player] {
        allPlayers
            .filter {
                $0.teamID == nil
                    && $0.contractYearsRemaining == 0
                    && !$0.isOnPracticeSquad
                    && !$0.isRetired
                    && !$0.isInjured
                    && !$0.isHoldingOut
                    && $0.overall < streetCeilingOverall
            }
            .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
    }

    // MARK: - The Signing

    /// Signs one street free agent to one club's active roster.
    ///
    /// Deliberately the same shape as `PracticeSquadEngine.signToActiveRoster`,
    /// down to the order of operations: pick the corresponding move, price the
    /// deal against the room it frees, release, then sign. Two in-season signing
    /// doors that opened in different orders would price the same transaction
    /// two ways.
    ///
    /// - Returns: `false` when the club has no room it is willing to make.
    private static func sign(
        _ player: Player,
        to club: Team,
        roster: [Player],
        capMode: CapMode,
        leagueYearRemaining: Double
    ) -> Bool {
        var release: Player?
        if roster.count >= activeRosterCeiling {
            release = roster
                .filter { !$0.isInjured }
                // The corresponding move may not empty a position room; filtered
                // into the candidate list rather than caught at the door, so a
                // club whose worst body is its backup quarterback releases the
                // next man down instead of the signing failing outright.
                .filter {
                    CapManagementEngine.releaseBlockReason(
                        player: $0,
                        team: club,
                        roster: roster
                    ) == nil
                }
                .min(by: { RosterValue.keepScore($0) < RosterValue.keepScore($1) })
            guard release != nil else { return false }
        }

        let minimum = ContractEngine.veteranMinimum(cap: club.salaryCap)
        if capMode != .sandbox {
            // The corresponding move frees `capSavings`, not the whole salary —
            // the released man's bonus acceleration stays on the books. Same
            // `leagueYearRemaining` the execution books, so the test and the
            // ledger cannot disagree.
            let freed = release.map {
                CapManagementEngine.releaseCapSplit(
                    player: $0,
                    contract: nil,
                    capMode: capMode,
                    leagueYearRemaining: leagueYearRemaining
                ).capSavings
            } ?? 0
            guard club.availableCap + freed >= minimum else { return false }
        }

        if let release {
            CapManagementEngine.applyRelease(
                player: release,
                team: club,
                // The candidate already cleared the floors; the door must not
                // refuse a corresponding move the club has been told it can make.
                authority: .leagueSweep,
                capMode: capMode,
                leagueYearRemaining: leagueYearRemaining
            )
        }

        // A man off the street lands on the 53, not in a camp bunk.
        //
        // Belt to the braces, NOT a repair: every door that puts a player on
        // the wire already clears the flag — `CapManagementEngine.applyRelease`
        // calls `CampRosterEngine.clearCampBodyStatus` unconditionally, the
        // league-year expiry in `FreeAgencyEngine` calls it too, and
        // `PracticeSquadEngine.release` writes `.active` outright. A camp body
        // also carries `contractYearsRemaining == campContractYears`, so a
        // still-flagged one could not satisfy `streetPool` in the first place.
        // The write stays because the flag is a ledger switch rather than a
        // label (`clearCampBodyStatus`: a man who kept it would be exempted
        // from the cap credit on his next, fully charged release), and an
        // invariant with one unguarded door is a bug waiting for a save file.
        // Set in the shared door so the AI's signing and the user's cannot
        // disagree about what a signing is.
        player.rosterStatus = .active
        ContractEngine.signPlayer(
            player: player,
            years: 1,
            annualSalary: minimum,
            team: club,
            capMode: capMode
        )
        return true
    }

    // MARK: - The User's Door (D6)

    /// Why the user's club cannot sign off the street right now.
    ///
    /// A reason rather than a `false`: this is the half of the market the user
    /// plays in, and "no" without a next action is the failure this screen was
    /// written to end.
    enum StreetRefusal: Equatable {
        /// Free agency itself is open — the market screen prices these men.
        case marketOpen
        /// The club has already used ``maxSigningsPerClubPerWeek`` in this
        /// bucket of the calendar. `limit` is that constant, quoted rather than
        /// retyped; `reopens` is when the rail turns over.
        case railSpent(limit: Int, reopens: RailReopen)
        /// The roster is at the ceiling in force this phase.
        case rosterFull(ceiling: Int)
        /// Not enough room for the veteran minimum. Both figures in $K.
        case shortOfCap(needed: Int, available: Int)
    }

    /// When a spent rail comes back — as much as the calendar can honestly
    /// promise, and no more.
    enum RailReopen: Equatable {
        /// The next numbered week. Only the regular season and deadline week
        /// can name one: `WeekAdvancer.advanceRegularSeasonWeek` increments
        /// `currentWeek` on every advance, week 18 included — the playoff
        /// transition then writes 19, which is the number the increment had
        /// already reached, so `week + 1` is never a week that does not happen.
        case week(Int)
        /// Everywhere else. `WeekAdvancer.advancePlayoffWeek` stops numbering
        /// at the conference finals (it moves to `.proBowl` with the week left
        /// where it is), and outside those two functions nothing moves
        /// `currentWeek` at all — so in the postseason and through the whole
        /// offseason there is no next week to name, only the next advance.
        case nextAdvance
    }

    /// The reopen this phase can promise. See ``RailReopen``.
    static func railReopen(phase: SeasonPhase, week: Int) -> RailReopen {
        switch phase {
        case .regularSeason, .tradeDeadline: return .week(week + 1)
        default:                             return .nextAdvance
        }
    }

    /// What happened when the user pressed Sign. `salary` is $K per year.
    enum StreetOutcome: Equatable {
        case signed(salary: Int)
        case refused(StreetRefusal)
    }

    /// Whether the street is open to the USER in this phase.
    ///
    /// Shut in `.freeAgency` and nowhere else. Not a balance dial: during the
    /// market the unsigned pool IS the free-agent class, and `streetPool`'s
    /// filter (`teamID == nil`, contract expired) cannot tell a March free agent
    /// from a September castoff. A minimum-salary side door open during those
    /// weeks would let the user buy men the market screen is bidding real money
    /// for, and price the same player two ways in the same afternoon.
    ///
    /// Every other phase is open, which is the point of the screen: the club
    /// that left free agency without a kicker finds out in the middle of camp,
    /// not in the following March.
    static func isOpenToUser(phase: SeasonPhase) -> Bool {
        phase != .freeAgency
    }

    /// The roster ceiling in force for the user this phase.
    ///
    /// The same split `RosterSummaryBar` prints in the roster header — 53 once
    /// the games count, `TradeValueEngine.offseasonRosterCeiling` (90) while the
    /// league legitimately carries a camp roster. Read from those two constants
    /// rather than retyped, so this door and that header cannot disagree about
    /// how many men the club is allowed to have.
    static func userRosterCeiling(phase: SeasonPhase) -> Int {
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs, .proBowl, .superBowl:
            return activeRosterCeiling
        default:
            return TradeValueEngine.offseasonRosterCeiling
        }
    }

    /// What a street deal costs this club: one year at the veteran minimum.
    ///
    /// `ContractEngine.veteranMinimum` scales with the club's own cap, which is
    /// why it takes the team and not a flat constant — the same call the AI half
    /// makes two screens up.
    static func streetSalary(for team: Team) -> Int {
        ContractEngine.veteranMinimum(cap: team.salaryCap)
    }

    // MARK: - The User's Weekly Rail

    /// One club's street signings inside one bucket of the calendar.
    ///
    /// The stamp is carried WITH the count rather than baked into the key, so
    /// the record is self-expiring: a count read against a different stamp is
    /// not a stale number to be swept, it is zero. That is the shape
    /// `scoutEvaluationCycle` uses for the same reason — nothing has to
    /// remember to reset it at a week boundary, and there is no boundary
    /// crossing that can leave a signing charged against the wrong week.
    struct WeeklyRail: Codable, Equatable {
        /// `season|phase|week` — see ``calendarStamp``.
        var stamp: String = ""
        var signings: Int = 0

        static let empty = WeeklyRail()
    }

    /// The bucket the rail counts in: `season|phase|week`.
    ///
    /// **Why the phase is in it.** `currentWeek` is a live counter in exactly
    /// three phases — `WeekAdvancer` sets it to 1 when the regular season
    /// opens, `advanceRegularSeasonWeek` increments it, `advancePlayoffWeek`
    /// increments it — and is frozen at last season's final value through every
    /// offseason stage. A `season|week` key alone would therefore make one
    /// bucket out of the entire offseason, and the club that came out of free
    /// agency without a kicker would get one signing to cover OTAs, camp,
    /// preseason and cutdowns together. With the phase in the stamp, a week of
    /// the season is a week and a stage of the offseason is a stage, and the
    /// rail turns over whenever the calendar moves — which is the whole of what
    /// ``RailReopen`` promises.
    static func calendarStamp(season: Int, phase: SeasonPhase, week: Int) -> String {
        "\(season)|\(phase.rawValue)|\(week)"
    }

    /// Base `UserDefaults` key, suffixed per save by `CareerScopedDefaults.key`.
    ///
    /// **Why `UserDefaults` and not a field.** This is per-save state with no
    /// column to live in — `Career` has `faVisitsUsed`, `interviewsUsed` and
    /// `workoutsUsed` but nothing for a per-week transaction count, and adding
    /// one is a schema change outside this door. `NegotiationLedger` and
    /// `CommittedCapLedger` are the same engine-side, careerID-scoped shape.
    ///
    /// Keyed by an explicit `careerID` rather than through
    /// `CareerScopedDefaults.scopedKey`, whose `WeekAdvancer.activeCareerID`
    /// fallback is the bare key: this screen is reachable in every phase, and a
    /// rail two saves shared would ration the wrong club.
    static let weeklyRailDefaultsKey = "streetSigningsThisWeek"

    private static func railKey(careerID: UUID) -> String {
        CareerScopedDefaults.key(weeklyRailDefaultsKey, careerID: careerID)
    }

    /// Street signings this club has already made in the current calendar
    /// bucket. `0` for a save that has never signed, and `0` the moment the
    /// calendar moves — see ``WeeklyRail``.
    static func userSigningsThisWeek(career: Career) -> Int {
        let stamp = calendarStamp(
            season: career.currentSeason,
            phase: career.currentPhase,
            week: career.currentWeek
        )
        guard let data = UserDefaults.standard.data(forKey: railKey(careerID: career.id)),
              let rail = try? JSONDecoder().decode(WeeklyRail.self, from: data),
              rail.stamp == stamp
        else { return 0 }
        return rail.signings
    }

    /// Charges one signing to the current bucket. Called by ``signForUser`` and
    /// nowhere else — the single place a user street deal is executed, so it is
    /// the single place the rail is spent.
    private static func recordUserSigning(career: Career) {
        let stamp = calendarStamp(
            season: career.currentSeason,
            phase: career.currentPhase,
            week: career.currentWeek
        )
        var rail = WeeklyRail(stamp: stamp, signings: userSigningsThisWeek(career: career))
        rail.signings += 1
        guard let data = try? JSONEncoder().encode(rail) else { return }
        UserDefaults.standard.set(data, forKey: railKey(careerID: career.id))
    }

    /// The reason the user cannot sign right now, or `nil` when he can.
    ///
    /// The roster and cap halves are deliberately NOT the AI's rule. The AI
    /// half makes its own corresponding move — it releases its lowest
    /// keep-score body to open the spot — because nobody is there to ask. Doing
    /// that on the user's behalf would cut a player he never chose, so a full
    /// roster is a refusal here and the release stays his decision, on the
    /// screens that already make it.
    ///
    /// The rail half IS the AI's rule, off the AI's own constant: one signing
    /// per club per calendar bucket, checked before the roster and the cap
    /// because it is the constraint the user cannot clear by acting on this
    /// screen — releasing a man would not buy him a second signing this week.
    ///
    /// - Parameter signingsThisWeek: from ``userSigningsThisWeek``. Passed in
    ///   rather than read here so this stays a pure function a view can call
    ///   once per render instead of once per row.
    static func userRefusal(
        career: Career,
        team: Team,
        roster: [Player],
        signingsThisWeek: Int
    ) -> StreetRefusal? {
        let phase = career.currentPhase
        guard isOpenToUser(phase: phase) else { return .marketOpen }
        if signingsThisWeek >= maxSigningsPerClubPerWeek {
            return .railSpent(
                limit: maxSigningsPerClubPerWeek,
                reopens: railReopen(phase: phase, week: career.currentWeek)
            )
        }
        let ceiling = userRosterCeiling(phase: phase)
        guard roster.count < ceiling else { return .rosterFull(ceiling: ceiling) }
        let salary = streetSalary(for: team)
        if career.capMode != .sandbox, team.availableCap < salary {
            return .shortOfCap(needed: salary, available: team.availableCap)
        }
        return nil
    }

    /// Signs one street free agent to the USER's active roster.
    ///
    /// The entry point `runWeeklyPass` has never had: that pass filters the user
    /// out (`teams.filter { $0.id != career.teamID }`) and its header says why —
    /// "the user's half is a screen". This is that screen's half of the door.
    /// Same pool, same one-year veteran minimum, same `ChurnDiag` stage, so a
    /// street DEAL is priced one way for all 32 clubs.
    ///
    /// Volume is matched on the rail that rations the pool:
    /// ``maxSigningsPerClubPerWeek`` is counted inside `runWeeklyPass`'s loop
    /// for the AI and off ``userSigningsThisWeek`` here, so all 32 clubs make
    /// one street signing per bucket of the calendar.
    ///
    /// The RATE is matched; the CALENDAR is not, and that is
    /// ``isOpenToUser``'s decision rather than this one. `runWeeklyPass` is
    /// guarded to `.regularSeason` and `.tradeDeadline`, so an AI club signs
    /// nobody off the street in the playoffs or across the offseason, while the
    /// user's door is open in every phase but `.freeAgency` — deliberately, so
    /// the club that came out of the market without a kicker has somewhere to
    /// go in August. He is rationed in those months rather than unrated, which
    /// is what the rail was asked for; whether the AI should be signing there
    /// too is a question for the pass.
    ///
    /// ``weeklyLeagueSigningCap`` is NOT matched, and saying so is not the same
    /// as defending it: it is a loop-local total inside `runWeeklyPass`, never
    /// persisted, so this door has nothing to read to know how many of the
    /// league's eight the AI has already spent this week. It cannot make the
    /// user's door more permissive than an AI club's — his per-club rail of one
    /// binds first either way — but a week in which the AI has genuinely
    /// exhausted the league's eight still leaves him a signing. Closing that
    /// needs a persisted league-week total, which is a decision for the pass,
    /// not for this screen.
    ///
    /// - Parameter roster: the club's active roster (`teamID == team.id`,
    ///   unretired), which the caller already holds.
    @discardableResult
    static func signForUser(
        _ player: Player,
        to team: Team,
        career: Career,
        roster: [Player]
    ) -> StreetOutcome {
        let phase = career.currentPhase
        let capMode = career.capMode
        // Re-read rather than trusting a count the caller is holding: the view's
        // cached number is for drawing the screen, this one is the door.
        if let refusal = userRefusal(
            career: career,
            team: team,
            roster: roster,
            signingsThisWeek: userSigningsThisWeek(career: career)
        ) {
            return .refused(refusal)
        }

        let salary = streetSalary(for: team)
        player.rosterStatus = .active
        ContractEngine.signPlayer(
            player: player,
            years: 1,
            annualSalary: salary,
            team: team,
            capMode: capMode
        )
        recordUserSigning(career: career)
        // `inSeasonFA` counts street signings made DURING the season — the stage
        // its own comment defines. An offseason signing through this same door
        // is a real transaction but not that stage, so it is not counted as one.
        if phase == .regularSeason || phase == .tradeDeadline || phase == .playoffs {
            ChurnDiag.record(ChurnDiag.inSeasonFA, player)
        }
        return .signed(salary: salary)
    }
}
