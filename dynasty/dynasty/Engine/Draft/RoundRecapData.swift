import Foundation

/// Pure data model + builder for the Round Recap card shown between draft
/// rounds. Vaihe 3.5 piece. The view layer renders this struct; the engine
/// fills it from the live `PickResult` stream and the user's
/// `DraftReputation` snapshots.
struct RoundRecapData {
    let round: Int
    let userPicks: [UserPickRow]
    let ownerTrustDelta: Int
    let fanMoodDelta: Int
    let lockerRoomDelta: Int
    let mediaNarrative: MediaNarrative
    let topStealsOverall: [LeagueStealRow]    // top 3 steals across the league this round

    struct UserPickRow: Identifiable {
        let id = UUID()
        let pickNumber: Int
        let playerName: String
        let position: Position
        let publicGrade: PickGrade
        let isGem: Bool
    }

    struct LeagueStealRow: Identifiable {
        let id = UUID()
        let pickNumber: Int
        let teamAbbrev: String
        let playerName: String
        let valueDelta: Int   // positive = steal magnitude (slots fallen)
    }
}

enum RoundRecapBuilder {

    /// Builds the recap data for one round.
    ///
    /// - Parameters:
    ///   - round: round number (1-based) being recapped.
    ///   - allPickResults: every PickResult fired in the *round* being
    ///       recapped. Caller should filter the global stream by `round`
    ///       before passing in.
    ///   - userTeamID: the user's team UUID, used to split user picks vs.
    ///       league-wide steals.
    ///   - beforeReputation: snapshot of user's reputation at the start of
    ///       the round. Pass nil for round 1.
    ///   - afterReputation: snapshot of user's reputation at the end of the
    ///       round.
    static func build(
        round: Int,
        allPickResults: [PickResult],
        userTeamID: UUID,
        beforeReputation: DraftReputation?,
        afterReputation: DraftReputation?
    ) -> RoundRecapData {
        // 1) User picks in this round, in pick order.
        let userPicks = allPickResults
            .filter { $0.isUserPick || $0.ownerOverride }
            .sorted { $0.pickNumber < $1.pickNumber }
            .map { result in
                RoundRecapData.UserPickRow(
                    pickNumber: result.pickNumber,
                    playerName: result.playerName,
                    position: result.position,
                    publicGrade: result.grade,
                    isGem: result.isGem
                )
            }

        // 2) Reputation deltas — zero if we don't have a "before" snapshot.
        let ownerDelta: Int
        let fanDelta: Int
        let lockerDelta: Int
        let narrative: MediaNarrative
        if let after = afterReputation {
            ownerDelta = after.ownerTrust - (beforeReputation?.ownerTrust ?? after.ownerTrust)
            fanDelta = after.fanMood - (beforeReputation?.fanMood ?? after.fanMood)
            lockerDelta = after.lockerRoomMood - (beforeReputation?.lockerRoomMood ?? after.lockerRoomMood)
            narrative = after.mediaNarrative
        } else {
            ownerDelta = 0
            fanDelta = 0
            lockerDelta = 0
            narrative = .neutral
        }

        // 3) Top steals across the league this round. Steals are picks where
        //    the public grade was A+ Steal or marked as a gem candidate.
        //    "valueDelta" here is approximated by slots fallen vs. expected
        //    (round * 32 ceiling) — we have no direct projection in
        //    PickResult, so we fall back to the gem flag for a stable sort.
        let leagueSteals: [RoundRecapData.LeagueStealRow] = allPickResults
            .filter { $0.grade == .stealAPlus || $0.grade == .hofTrack || $0.isGem }
            .sorted(by: stealSort)
            .prefix(3)
            .map { result in
                RoundRecapData.LeagueStealRow(
                    pickNumber: result.pickNumber,
                    teamAbbrev: result.teamAbbrev,
                    playerName: result.playerName,
                    valueDelta: stealMagnitude(for: result)
                )
            }

        return RoundRecapData(
            round: round,
            userPicks: userPicks,
            ownerTrustDelta: ownerDelta,
            fanMoodDelta: fanDelta,
            lockerRoomDelta: lockerDelta,
            mediaNarrative: narrative,
            topStealsOverall: Array(leagueSteals)
        )
    }

    // MARK: - Sort helpers

    /// Bigger steals first; ties broken by earliest pick.
    private static func stealSort(_ a: PickResult, _ b: PickResult) -> Bool {
        let am = stealMagnitude(for: a)
        let bm = stealMagnitude(for: b)
        if am != bm { return am > bm }
        return a.pickNumber < b.pickNumber
    }

    /// Heuristic magnitude: hofTrack > stealAPlus > generic gem; deeper picks
    /// get a multiplier so a gem at #50 outranks a gem at #5.
    private static func stealMagnitude(for result: PickResult) -> Int {
        let base: Int
        switch result.grade {
        case .hofTrack:   base = 30
        case .stealAPlus: base = 20
        default:          base = result.isGem ? 10 : 0
        }
        // Later picks earn more steal credit.
        return base + (result.pickNumber / 8)
    }
}
