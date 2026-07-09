import Foundation
import SwiftData

/// R23 — Compensatory draft picks, simplified NFL formula.
///
/// The league tracks every contract expiry ("departure ledger"). At the end
/// of free agency, each team's qualifying losses are netted against its
/// qualifying gains and the difference converts into extra picks in rounds
/// 3–7 of the upcoming draft.
///
/// Simplified formula (vs. the real, unpublished NFL one):
/// - A qualifying CFA is a player whose contract EXPIRED (cuts never count)
///   and who then signed with a different team for at least 0.6% of the cap.
/// - Net losses = qualifying losses − qualifying gains (count-based offset).
/// - A team gets one pick per net loss, max 4, for its highest-paid losses.
/// - The round comes from the NEW contract's salary as % of the league cap:
///   ≥ 5.0% → R3, ≥ 3.5% → R4, ≥ 2.25% → R5, ≥ 1.25% → R6, ≥ 0.6% → R7.
///
/// The ledger lives in UserDefaults (same persistence pattern as
/// `FASigningTracker` / `NegotiationLockRegistry`): shared across careers on
/// one device, cleared every time the awards are settled.
enum CompensatoryPickEngine {

    private static let departuresKey    = "compPickDepartures"
    private static let pendingAwardsKey = "compPickPendingAwards"

    // MARK: - Departure Ledger

    /// Records that a player's contract expired while on `formerTeamID`.
    /// Called from the two contract-expiry sites (week 18 and the new league
    /// year) — cut players never pass through here, so they can't earn picks.
    static func recordDeparture(playerID: UUID, formerTeamID: UUID) {
        var map = rawDepartures()
        map[playerID.uuidString] = formerTeamID.uuidString
        UserDefaults.standard.set(map, forKey: departuresKey)
    }

    /// playerID → team the player's contract expired on.
    static func departures() -> [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for (playerKey, teamValue) in rawDepartures() {
            if let playerID = UUID(uuidString: playerKey),
               let teamID = UUID(uuidString: teamValue) {
                result[playerID] = teamID
            }
        }
        return result
    }

    static func clearDepartures() {
        UserDefaults.standard.removeObject(forKey: departuresKey)
    }

    private static func rawDepartures() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: departuresKey) as? [String: String]) ?? [:]
    }

    // MARK: - Award Computation

    struct CompAward: Codable {
        let teamID: UUID
        let round: Int
        let lostPlayerName: String
        /// The lost player's NEW annual salary in thousands (decides the round).
        let lostPlayerSalary: Int
    }

    /// Round for a new contract's annual salary, or `nil` when the deal is too
    /// small to qualify as a compensatory free agent at all.
    static func round(forSalary salary: Int, cap: Int) -> Int? {
        guard cap > 0 else { return nil }
        let pct = Double(salary) / Double(cap)
        switch pct {
        case 0.050...: return 3
        case 0.035...: return 4
        case 0.0225...: return 5
        case 0.0125...: return 6
        case 0.006...: return 7
        default:       return nil
        }
    }

    /// Settles the ledger: compares where each departed player ended up
    /// against where he came from and converts net losses into awards.
    static func computeAwards(
        departures: [UUID: UUID],
        allPlayers: [Player],
        allTeams: [Team]
    ) -> [CompAward] {
        guard !departures.isEmpty else { return [] }

        let avgCap = allTeams.isEmpty
            ? 265_000
            : allTeams.reduce(0) { $0 + $1.salaryCap } / allTeams.count
        let playersByID = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })

        struct QualifyingMove {
            let playerName: String
            let newSalary: Int
            let round: Int
        }

        var lossesByTeam: [UUID: [QualifyingMove]] = [:]
        var gainsByTeam: [UUID: Int] = [:]

        for (playerID, formerTeamID) in departures {
            guard let player = playersByID[playerID],
                  let newTeamID = player.teamID,        // unsigned FAs don't count
                  newTeamID != formerTeamID,            // re-signings don't count
                  let round = round(forSalary: player.annualSalary, cap: avgCap)
            else { continue }

            lossesByTeam[formerTeamID, default: []].append(QualifyingMove(
                playerName: player.fullName,
                newSalary: player.annualSalary,
                round: round
            ))
            gainsByTeam[newTeamID, default: 0] += 1
        }

        var awards: [CompAward] = []
        for (teamID, losses) in lossesByTeam {
            let gains = gainsByTeam[teamID] ?? 0
            let netLosses = losses.count - gains
            guard netLosses > 0 else { continue }

            // Award the highest-paid losses first, capped at 4 picks per team.
            let compensated = losses
                .sorted { $0.newSalary > $1.newSalary }
                .prefix(min(netLosses, 4))

            for move in compensated {
                awards.append(CompAward(
                    teamID: teamID,
                    round: move.round,
                    lostPlayerName: move.playerName,
                    lostPlayerSalary: move.newSalary
                ))
            }
        }

        return awards.sorted { $0.round < $1.round }
    }

    /// Projection of the awards the given team would earn if free agency ended
    /// right now — used by the FA summary screen so the "expected comp picks"
    /// display matches what the league actually awards.
    static func projectedAwards(
        forTeam teamID: UUID,
        allPlayers: [Player],
        allTeams: [Team]
    ) -> [CompAward] {
        computeAwards(departures: departures(), allPlayers: allPlayers, allTeams: allTeams)
            .filter { $0.teamID == teamID }
    }

    // MARK: - Pending Awards (bridge from FA close to draft-order generation)

    static func stashPendingAwards(_ awards: [CompAward]) {
        guard let data = try? JSONEncoder().encode(awards) else { return }
        UserDefaults.standard.set(data, forKey: pendingAwardsKey)
    }

    static func pendingAwards() -> [CompAward] {
        guard let data = UserDefaults.standard.data(forKey: pendingAwardsKey),
              let awards = try? JSONDecoder().decode([CompAward].self, from: data) else {
            return []
        }
        return awards
    }

    static func clearPendingAwards() {
        UserDefaults.standard.removeObject(forKey: pendingAwardsKey)
    }

    // MARK: - Applying Awards to a Pick Pool

    /// Creates the compensatory `DraftPick` rows, slots them at the END of
    /// their rounds, and renumbers the whole pool sequentially so pick numbers
    /// stay contiguous. Existing picks keep their relative order.
    ///
    /// Returns the newly created picks; the caller inserts them into the
    /// model context (existing pool rows are mutated in place).
    static func applyAwards(
        _ awards: [CompAward],
        toPickPool pool: [DraftPick],
        seasonYear: Int,
        teamAbbrs: [UUID: String]
    ) -> [DraftPick] {
        guard !awards.isEmpty else { return [] }

        let newPicks: [DraftPick] = awards.map { award in
            DraftPick(
                seasonYear: seasonYear,
                round: award.round,
                pickNumber: 0, // assigned below
                originalTeamID: award.teamID,
                currentTeamID: award.teamID,
                teamAbbreviation: teamAbbrs[award.teamID]
            )
        }

        let newPickIDs = Set(newPicks.map(\.id))
        let combined = (pool + newPicks).sorted { lhs, rhs in
            if lhs.round != rhs.round { return lhs.round < rhs.round }
            let lhsComp = newPickIDs.contains(lhs.id)
            let rhsComp = newPickIDs.contains(rhs.id)
            if lhsComp != rhsComp { return rhsComp } // base picks before comp picks
            return lhs.pickNumber < rhs.pickNumber
        }

        for (index, pick) in combined.enumerated() {
            pick.pickNumber = index + 1
        }

        return newPicks
    }
}
