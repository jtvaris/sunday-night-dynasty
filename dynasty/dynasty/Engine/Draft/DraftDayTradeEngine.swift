import Foundation

// MARK: - Draft Day Trade Engine (R24)
//
// Pick-for-pick trade logic inside the live draft:
// - AI partners can offer to TRADE UP into the user's pick when the user is
//   1-3 picks from the clock (caller rolls the dice, this engine builds the
//   package).
// - The user can request a TRADE DOWN while on the clock; willingness rises
//   when top-of-board prospects are still available for teams picking behind.
//
// All valuation goes through the R21 `TradeValueEngine` Jimmy Johnson curves —
// no parallel value logic. Only current-draft picks change hands (future-year
// picks don't exist as `DraftPick` rows during the draft), so accepting an
// offer is just flipping `currentTeamID` and the draft continues in order.
enum DraftDayTradeEngine {

    // MARK: - Offer model

    /// A pick-for-pick swap between the user and an AI partner. `userGives` /
    /// `userGets` reference real `DraftPick` rows of the current draft.
    struct PickSwapOffer: Identifiable {
        let id = UUID()
        let partnerTeamID: UUID
        let partnerAbbreviation: String
        let userGives: [DraftPick]
        let userGets: [DraftPick]
        let motive: String
        let userGivesValue: Int      // JJ points via TradeValueEngine
        let userGetsValue: Int
    }

    // MARK: - AI trade-up into the user's pick

    /// Builds an offer where an AI team jumps up into `userPick`, paying with
    /// its own later picks in this draft. Requires the partner to covet a
    /// top-6 board prospect at one of its top-3 need positions, so the user
    /// can always infer WHY the offer came in. Returns nil when no believable
    /// partner/package exists. The caller owns the per-pick dice roll.
    static func aiTradeUpOffer(
        userPick: DraftPick,
        picks: [DraftPick],
        currentPickIndex: Int,
        userTeamID: UUID,
        teamsByID: [UUID: Team],
        rosters: [UUID: [Player]],
        availableProspects: [CollegeProspect],
        publicBoardRanks: [UUID: Int],
        currentSeason: Int
    ) -> PickSwapOffer? {
        let topBoard = topOfBoard(availableProspects, publicBoardRanks: publicBoardRanks, limit: 6)
        let candidates = partnerCandidates(
            after: userPick,
            picks: picks,
            currentPickIndex: currentPickIndex,
            userTeamID: userTeamID,
            maxSlide: 24
        )

        for candidate in candidates.shuffled() {
            guard let team = teamsByID[candidate.teamID] else { continue }
            let needs = DraftEngine.topTeamNeeds(roster: rosters[candidate.teamID] ?? [], limit: 3)
            guard let target = topBoard.first(where: { needs.contains($0.position) }) else { continue }
            let motive = "\(team.abbreviation) want to jump up to #\(userPick.pickNumber) — they're targeting a \(target.position.rawValue) before the board turns."
            if let offer = buildOffer(
                userPick: userPick,
                partner: team,
                partnerPicks: candidate.picks,
                motive: motive,
                currentSeason: currentSeason
            ) {
                return offer
            }
        }
        return nil
    }

    // MARK: - User-initiated trade down

    /// Searches for an AI team willing to move up into the pick the user has
    /// on the clock. Per-partner willingness: ~65 % when a top-8 board
    /// prospect sits at one of the partner's top-3 needs, ~20 % otherwise,
    /// plus up to +15 % when consensus top talent is sliding to this slot.
    static func userTradeDownOffer(
        currentPick: DraftPick,
        picks: [DraftPick],
        currentPickIndex: Int,
        userTeamID: UUID,
        teamsByID: [UUID: Team],
        rosters: [UUID: [Player]],
        availableProspects: [CollegeProspect],
        publicBoardRanks: [UUID: Int],
        currentSeason: Int
    ) -> PickSwapOffer? {
        let topBoard = topOfBoard(availableProspects, publicBoardRanks: publicBoardRanks, limit: 8)
        // Consensus value sliding to this slot makes moving up more tempting.
        let slidingTalent = availableProspects.filter {
            (publicBoardRanks[$0.id] ?? 999) <= currentPick.pickNumber + 3
        }.count
        let candidates = partnerCandidates(
            after: currentPick,
            picks: picks,
            currentPickIndex: currentPickIndex,
            userTeamID: userTeamID,
            maxSlide: 18
        )

        for candidate in candidates.shuffled() {
            guard let team = teamsByID[candidate.teamID] else { continue }
            let needs = DraftEngine.topTeamNeeds(roster: rosters[candidate.teamID] ?? [], limit: 3)
            let target = topBoard.first(where: { needs.contains($0.position) })
            let willingness = (target != nil ? 0.65 : 0.20) + 0.05 * Double(min(3, slidingTalent))
            guard Double.random(in: 0..<1) < willingness else { continue }

            let motive: String
            if let target {
                motive = "\(team.abbreviation) bite: they'll move up for a \(target.position.rawValue) still on the board."
            } else {
                motive = "\(team.abbreviation) like the value at #\(currentPick.pickNumber) and are willing to pay the chart price."
            }
            if let offer = buildOffer(
                userPick: currentPick,
                partner: team,
                partnerPicks: candidate.picks,
                motive: motive,
                currentSeason: currentSeason
            ) {
                return offer
            }
        }
        return nil
    }

    // MARK: - Package construction

    /// Builds the pick package the partner pays: its earliest later pick as
    /// the anchor, plus the cheapest sweeteners that close the chart-value
    /// gap (max 3 picks, 98-145 % of the user pick's value — the mover-up
    /// pays a small classic premium).
    private static func buildOffer(
        userPick: DraftPick,
        partner: Team,
        partnerPicks: [DraftPick],
        motive: String,
        currentSeason: Int
    ) -> PickSwapOffer? {
        guard let anchor = partnerPicks.first else { return nil }
        func value(_ pick: DraftPick) -> Int {
            TradeValueEngine.pickTradeValue(pick: pick, currentSeason: currentSeason)
        }

        let targetValue = value(userPick)
        var package = [anchor]
        var packageValue = value(anchor)

        // Sweeteners sorted cheapest-first; prefer the smallest pick that
        // closes the remaining gap, otherwise keep stacking the largest left.
        var remaining = partnerPicks.dropFirst()
            .map { (pick: $0, value: value($0)) }
            .sorted { $0.value < $1.value }
        while packageValue < targetValue, package.count < 3, !remaining.isEmpty {
            let gap = targetValue - packageValue
            let chosen: (pick: DraftPick, value: Int)
            if let idx = remaining.firstIndex(where: { $0.value >= gap }) {
                chosen = remaining.remove(at: idx)
            } else {
                chosen = remaining.removeLast()
            }
            package.append(chosen.pick)
            packageValue += chosen.value
        }

        let ratio = Double(packageValue) / Double(max(1, targetValue))
        guard ratio >= 0.98, ratio <= 1.45 else { return nil }

        return PickSwapOffer(
            partnerTeamID: partner.id,
            partnerAbbreviation: partner.abbreviation,
            userGives: [userPick],
            userGets: package,
            motive: motive,
            userGivesValue: targetValue,
            userGetsValue: packageValue
        )
    }

    // MARK: - Helpers

    /// Teams (≠ user) owning incomplete picks 2...maxSlide slots after the
    /// reference pick, with each team's picks sorted by pick number.
    private static func partnerCandidates(
        after referencePick: DraftPick,
        picks: [DraftPick],
        currentPickIndex: Int,
        userTeamID: UUID,
        maxSlide: Int
    ) -> [(teamID: UUID, picks: [DraftPick])] {
        var byTeam: [UUID: [DraftPick]] = [:]
        for pick in picks.dropFirst(currentPickIndex) where !pick.isComplete {
            guard pick.currentTeamID != userTeamID,
                  pick.pickNumber > referencePick.pickNumber else { continue }
            byTeam[pick.currentTeamID, default: []].append(pick)
        }
        return byTeam.compactMap { teamID, teamPicks in
            let sorted = teamPicks.sorted { $0.pickNumber < $1.pickNumber }
            guard let first = sorted.first else { return nil }
            let slide = first.pickNumber - referencePick.pickNumber
            guard slide >= 2, slide <= maxSlide else { return nil }
            return (teamID, sorted)
        }
    }

    /// Top of the PUBLIC board (consensus ranks only — no hidden data leaks).
    private static func topOfBoard(
        _ prospects: [CollegeProspect],
        publicBoardRanks: [UUID: Int],
        limit: Int
    ) -> [(position: Position, rank: Int)] {
        prospects
            .compactMap { prospect -> (position: Position, rank: Int)? in
                guard let rank = publicBoardRanks[prospect.id] else { return nil }
                return (prospect.position, rank)
            }
            .sorted { $0.rank < $1.rank }
            .prefix(limit)
            .map { $0 }
    }
}
