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

        ContractEngine.signPlayer(
            player: player,
            years: 1,
            annualSalary: minimum,
            team: club,
            capMode: capMode
        )
        return true
    }
}
