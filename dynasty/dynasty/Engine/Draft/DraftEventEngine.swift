import Foundation

/// Lightweight, in-memory representation of a planned draft event.
/// (Persisted form is `DraftEvent` — `DraftDayCoordinator` converts when consuming.)
struct PlannedDraftEvent {
    let sequence: Int
    let type: DraftEventType
    let teamID: UUID?
    let pickNumber: Int?
    let round: Int?
    /// Convenience accessor for `pickMade` / `bigDrop` — duplicated from metadata for ergonomic access.
    let prospectID: UUID?
    let metadata: Metadata

    enum Metadata {
        case none
        case pick(prospectID: UUID, isPlayerTeam: Bool)
        case bigDrop(prospectID: UUID, expectedPick: Int, actualPick: Int)
        case positionRun(position: String, count: Int)
        case round(roundNumber: Int)
    }
}

/// Stateless, deterministic event-stream generator for a single draft.
///
/// Vaihe 1 surface area: pickit, round transitions, on-the-clock notifications,
/// + bigDrop / positionRun tells. No trade offers, no reactions, no scout interrupts yet.
enum DraftEventEngine {

    /// Generates the entire deterministic event stream for one draft.
    /// The caller must hold the prospects list constant during consumption.
    ///
    /// - Parameters:
    ///   - seed: Seed for the internal RNG (currently unused by `aiMakePick`, kept for forward-compat
    ///     reactions/trade flavor).
    ///   - teams: All league teams.
    ///   - teamRosters: Map of teamID → current roster.
    ///   - prospects: All available college prospects entering the draft.
    ///   - seasonYear: The draft year (used by callers when persisting events).
    ///   - existingPicks: Pre-generated draft order (e.g. via `DraftEngine.generateDraftOrder`).
    static func makeStream(
        seed: UInt64,
        teams: [Team],
        teamRosters: [UUID: [Player]],
        prospects: [CollegeProspect],
        seasonYear: Int,
        existingPicks: [DraftPick]
    ) -> [PlannedDraftEvent] {
        var rng = SeededGenerator(state: seed == 0 ? 1 : seed)
        _ = rng.next() // burn one to avoid trivially-identical first values

        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        var events: [PlannedDraftEvent] = []
        var sequence = 0

        // 1) draftStarted
        events.append(PlannedDraftEvent(
            sequence: sequence,
            type: .draftStarted,
            teamID: nil,
            pickNumber: nil,
            round: nil,
            prospectID: nil,
            metadata: .none
        ))
        sequence += 1

        // Sort picks deterministically and walk round-by-round.
        let orderedPicks = existingPicks.sorted { $0.pickNumber < $1.pickNumber }
        let picksByRound = Dictionary(grouping: orderedPicks, by: { $0.round })
        let rounds = picksByRound.keys.sorted()

        // Local mutable copy of the available prospect pool — shrinks as picks are made.
        var availableProspects = prospects

        // Sliding window of last picks for position-run detection.
        var recentPositions: [Position] = []

        for round in rounds {
            // 2a) roundTransition
            events.append(PlannedDraftEvent(
                sequence: sequence,
                type: .roundTransition,
                teamID: nil,
                pickNumber: nil,
                round: round,
                prospectID: nil,
                metadata: .round(roundNumber: round)
            ))
            sequence += 1

            guard let roundPicks = picksByRound[round] else { continue }
            let sortedRoundPicks = roundPicks.sorted { $0.pickNumber < $1.pickNumber }

            for pick in sortedRoundPicks {
                let teamID = pick.currentTeamID

                // 2b) onTheClock
                events.append(PlannedDraftEvent(
                    sequence: sequence,
                    type: .onTheClock,
                    teamID: teamID,
                    pickNumber: pick.pickNumber,
                    round: round,
                    prospectID: nil,
                    metadata: .none
                ))
                sequence += 1

                // 2c) pickMade — pick a prospect using DraftEngine's AI.
                guard !availableProspects.isEmpty else { break }
                guard let team = teamsByID[teamID] else { continue }

                let roster = teamRosters[teamID] ?? []
                let chosen = DraftEngine.aiMakePick(
                    team: team,
                    availableProspects: availableProspects,
                    teamRoster: roster
                )

                events.append(PlannedDraftEvent(
                    sequence: sequence,
                    type: .pickMade,
                    teamID: teamID,
                    pickNumber: pick.pickNumber,
                    round: round,
                    prospectID: chosen.id,
                    metadata: .pick(prospectID: chosen.id, isPlayerTeam: false)
                ))
                sequence += 1

                // 2d) bigDrop — if the prospect was projected materially earlier than this slot.
                if let projection = chosen.draftProjection,
                   projection > 0,
                   pick.pickNumber > projection + 8 {
                    events.append(PlannedDraftEvent(
                        sequence: sequence,
                        type: .bigDrop,
                        teamID: teamID,
                        pickNumber: pick.pickNumber,
                        round: round,
                        prospectID: chosen.id,
                        metadata: .bigDrop(
                            prospectID: chosen.id,
                            expectedPick: projection,
                            actualPick: pick.pickNumber
                        )
                    ))
                    sequence += 1
                }

                // 2e) positionRun — three picks in a row at the same position.
                recentPositions.append(chosen.position)
                if recentPositions.count > 3 {
                    recentPositions.removeFirst(recentPositions.count - 3)
                }
                if recentPositions.count == 3,
                   let first = recentPositions.first,
                   recentPositions.allSatisfy({ $0 == first }) {
                    events.append(PlannedDraftEvent(
                        sequence: sequence,
                        type: .positionRun,
                        teamID: nil,
                        pickNumber: pick.pickNumber,
                        round: round,
                        prospectID: nil,
                        metadata: .positionRun(position: first.rawValue, count: 3)
                    ))
                    sequence += 1
                }

                // Remove the chosen prospect from the available pool.
                if let idx = availableProspects.firstIndex(where: { $0.id == chosen.id }) {
                    availableProspects.remove(at: idx)
                }
            }
        }

        // 3) draftCompleted
        events.append(PlannedDraftEvent(
            sequence: sequence,
            type: .draftCompleted,
            teamID: nil,
            pickNumber: nil,
            round: nil,
            prospectID: nil,
            metadata: .none
        ))

        return events
    }
}

// MARK: - Seeded RNG

/// Deterministic linear-congruential generator. Knuth MMIX constants.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
