import Foundation
import SwiftData

// MARK: - WaiverWireEngine

/// The 24h post-cut waiver window: worst record claims first.
///
/// ## What this used to be (F-46)
///
/// The priority order was right, the per-club interest read was right, and then
/// the claim wrote `RosterCut.claimedByTeamID`, `player.cutByTeamID` and
/// `player.cutAt` — and **never `player.teamID`**. The claimed man stayed a free
/// agent. The only readers of `claimedByTeamID` in the whole app were a banner
/// and a filter, so *the one structural mechanism in the game that hands talent
/// to bad teams was a notification*. `REBUILD_VIABILITY_ANALYSIS.md`
/// recommendation 13 found it and it was still true two audits later.
///
/// It also only ever ran over the USER's camp cuts: `trimAIRosters` releases
/// ~34 men per AI club on one afternoon and files no `RosterCut` row (it hands
/// `applyRelease` no `ModelContext`, deliberately — a league's worth of AI churn
/// has no business in the user's cap ledger). So the wire processed one club's
/// cuts and produced no transaction from them.
///
/// ## What it is now
///
/// ``runWindow`` is the real thing: priority by record, per-club interest, a
/// corresponding move when the claimant is full, a cap charge, and
/// `player.teamID` actually moving. It takes a plain list of players, so both
/// pools go through it — the user's `RosterCut` rows via ``processWaivers`` and
/// the whole league's cutdown pool in memory via ``runWindow`` directly.
///
/// **Why worst-record-first matters more than it looks.** `diag balance` reads
/// year-over-year win correlation at 0.67-0.74 against a real 0.32 and 0 % of
/// last season's bottom four reaching the playoff field. Waiver priority is one
/// of the five mechanisms real parity is actually made of, and until now it
/// moved nobody.
@MainActor
enum WaiverWireEngine {

    // MARK: - League Rules

    /// A claiming club may not exceed the active-roster ceiling; at 53 it has
    /// to make a corresponding move, exactly as a real club does.
    static let activeRosterCeiling = 53

    /// Claims one club will make in a single window.
    ///
    /// The cutdown pool is ~34 men per club, so the wire carries roughly a
    /// thousand players and the worst club in the league has first refusal on
    /// every one of them. Uncapped, the priority advantage stops being an edge
    /// and becomes a rebuild-in-an-afternoon: it would keep claiming until no
    /// man on the wire beat its own 53rd, which on a bad roster is a long way
    /// down. Real clubs claim a handful on cutdown weekend — the priority is
    /// worth the first few names, not the whole board — and a cap is also what
    /// keeps the corresponding moves from churning a third of the league's
    /// active rosters in one advance.
    static let maxClaimsPerClubPerWindow = 4

    /// Contract years a claim is written for. A claim takes over the balance of
    /// the man's deal in the real league; here every in-season signing door
    /// (`PracticeSquadEngine.signToActiveRoster`, the AI refill) writes one year
    /// at the minimum, and a second convention would just be a second number to
    /// keep in sync.
    static let claimContractYears = 1

    // MARK: - Types

    struct WaiverClaim {
        let cutPlayerID: UUID
        let claimingTeamID: UUID
        let priority: Int
    }

    // MARK: - Public API

    /// Runs the window over the user's filed camp cuts. Thin adapter: resolves
    /// the `RosterCut` rows to players, runs ``runWindow``, and stamps the row
    /// so the existing claim banner still reads.
    @discardableResult
    static func processWaivers(
        cuts: [RosterCut],
        teams: [Team],
        capMode: CapMode,
        allPlayers: [Player],
        modelContext: ModelContext
    ) -> [WaiverClaim] {
        guard !cuts.isEmpty else { return [] }

        let cutPlayerIDs = cuts.map(\.playerID)
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { cutPlayerIDs.contains($0.id) }
        )
        let players = (try? modelContext.fetch(playerDescriptor)) ?? []
        let playerByID: [UUID: Player] = Dictionary(
            players.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
        )

        // The cutting club may not reclaim its own man, and the row is the only
        // place that memory lives for a user cut.
        var candidates: [(player: Player, cutBy: UUID?)] = []
        var rowByPlayer: [UUID: RosterCut] = [:]
        for cut in cuts where cut.claimedByTeamID == nil {
            guard let player = playerByID[cut.playerID] else { continue }
            candidates.append((player, cut.teamID))
            rowByPlayer[cut.playerID] = cut
        }

        let claims = runWindow(
            candidates: candidates,
            teams: teams,
            capMode: capMode,
            allPlayers: allPlayers
        )
        for claim in claims {
            rowByPlayer[claim.cutPlayerID]?.claimedByTeamID = claim.claimingTeamID
        }
        return claims
    }

    /// **The window itself.** One pass over a pool of released men, each offered
    /// to the league in waiver-priority order until somebody takes him.
    ///
    /// - Parameters:
    ///   - candidates: released players, each with the club that released him
    ///     (which may not claim him back).
    ///   - teams: every club, for records, cap room and the corresponding move.
    ///   - allPlayers: the league, for roster counts and the corresponding move.
    @discardableResult
    static func runWindow(
        candidates: [(player: Player, cutBy: UUID?)],
        teams: [Team],
        capMode: CapMode,
        allPlayers: [Player]
    ) -> [WaiverClaim] {
        guard !candidates.isEmpty, !teams.isEmpty else { return [] }

        // Waiver priority: worst record first. Ties by losses desc then id, so
        // the same league in the same state always produces the same order.
        let priorityOrder = teams.sorted { lhs, rhs in
            if lhs.wins != rhs.wins { return lhs.wins < rhs.wins }
            if lhs.losses != rhs.losses { return lhs.losses > rhs.losses }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        // Roster counts are maintained incrementally: a club that claims two men
        // in one window has to see the first one when it considers the second,
        // or the ceiling is not a ceiling.
        var rosterByTeam: [UUID: [Player]] = [:]
        for player in allPlayers where !player.isRetired {
            guard let teamID = player.teamID else { continue }
            rosterByTeam[teamID, default: []].append(player)
        }

        var claims: [WaiverClaim] = []
        var claimsByTeam: [UUID: Int] = [:]

        for candidate in candidates {
            let player = candidate.player
            // He may already have been signed by an earlier pass this advance.
            guard player.teamID == nil, !player.isRetired, !player.isOnPracticeSquad else { continue }
            let interestThreshold = waiverInterestThreshold(for: player)

            for (index, club) in priorityOrder.enumerated() {
                if club.id == candidate.cutBy { continue }
                guard claimsByTeam[club.id, default: 0] < maxClaimsPerClubPerWindow else { continue }
                guard teamInterest(player: player, teamID: club.id) >= interestThreshold else { continue }

                var roster = rosterByTeam[club.id] ?? []
                guard let release = correspondingMove(
                    for: player,
                    club: club,
                    roster: roster
                ) else { continue }

                let minimum = ContractEngine.veteranMinimum(cap: club.salaryCap)
                if capMode != .sandbox {
                    // The corresponding move frees `capSavings`, not the whole
                    // salary — the released man's bonus acceleration stays on
                    // the books. Same split the execution books below.
                    let freed = release.map {
                        CapManagementEngine.releaseCapSplit(
                            player: $0,
                            contract: nil,
                            capMode: capMode,
                            leagueYearRemaining: 1.0
                        ).capSavings
                    } ?? 0
                    guard club.availableCap + freed >= minimum else { continue }
                }

                if let release {
                    CapManagementEngine.applyRelease(
                        player: release,
                        team: club,
                        // The candidate list already cleared the positional
                        // floors; the door must not refuse a corresponding move
                        // the club has been told it can make.
                        authority: .leagueSweep,
                        capMode: capMode,
                        leagueYearRemaining: 1.0
                    )
                    roster.removeAll { $0.id == release.id }
                }

                ContractEngine.signPlayer(
                    player: player,
                    years: claimContractYears,
                    annualSalary: minimum,
                    team: club,
                    capMode: capMode
                )
                // The cut stamp survives the claim: `RevengeTourEngine` and the
                // practice-squad own-cut bonus both read "who let him go", and
                // that is still true of the club that released him.
                player.cutByTeamID = candidate.cutBy
                player.cutAt = .now
                roster.append(player)
                rosterByTeam[club.id] = roster
                claimsByTeam[club.id, default: 0] += 1

                ChurnDiag.record(ChurnDiag.claim, player)
                claims.append(WaiverClaim(
                    cutPlayerID: player.id,
                    claimingTeamID: club.id,
                    priority: index
                ))
                break
            }
        }

        return claims.sorted { $0.priority < $1.priority }
    }

    // MARK: - Heuristics

    /// The corresponding move a claim needs, or `nil` if the club will not make
    /// one.
    ///
    /// Below the ceiling a claim is free and the answer is `.some(nil)` — no
    /// release needed. At the ceiling the club must give a spot back, and it
    /// only will when the claimed man is genuinely better than the body he
    /// displaces: `keepScore`, the same key the cutdown ladder, the poach board
    /// and the practice-squad fill all rank with. That comparison is what stops
    /// a full league from churning its 53rd man 32 times a window for no gain.
    ///
    /// The nested optional is deliberate — "no release needed" and "no legal
    /// release exists" are different answers and the caller must not conflate
    /// them.
    private static func correspondingMove(
        for player: Player,
        club: Team,
        roster: [Player]
    ) -> Player?? {
        guard roster.count >= activeRosterCeiling else { return .some(nil) }
        let candidate = roster
            .filter { !$0.isInjured }
            .filter {
                CapManagementEngine.releaseBlockReason(
                    player: $0,
                    team: club,
                    roster: roster
                ) == nil
            }
            .min(by: { RosterValue.keepScore($0) < RosterValue.keepScore($1) })
        guard let candidate,
              RosterValue.keepScore(candidate) < RosterValue.keepScore(player)
        else { return nil }
        return .some(candidate)
    }

    /// OVR floor a player must clear for at least one team to claim.
    private static func waiverInterestThreshold(for player: Player) -> Double {
        // Veterans (3+ years) need a higher OVR to be claimed (younger players preferred).
        let baseFloor: Double = player.yearsPro >= 3 ? 70.0 : 60.0
        // Injured players are claimed less often — raise the bar.
        let injuryBump: Double = player.isInjured ? 8.0 : 0.0
        return baseFloor + injuryBump
    }

    /// Team-interest score on this specific player. Stable per (player, team) pair.
    private static func teamInterest(player: Player, teamID: UUID) -> Double {
        // OVR + deterministic per-(player,team) jitter so different teams favor different players.
        let jitter = Double(abs(player.id.hashValue ^ teamID.hashValue) % 17) - 8.0
        return Double(player.overall) + jitter
    }
}
