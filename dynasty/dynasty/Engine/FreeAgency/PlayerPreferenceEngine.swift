import Foundation

/// Generates and evaluates hidden free-agent preferences (A6 in the FA Drama
/// design brief). Preferences are deterministic from the player UUID so they
/// are stable across save/load even though they are not persisted.
enum PlayerPreferenceEngine {

    /// Generates 1-2 hidden preferences for a player. Deterministic from
    /// `playerID` hash so it is reproducible without persistence.
    static func generatePreferences(
        playerID: UUID,
        position: Position
    ) -> [PlayerPreferenceTag] {
        var rng = SeededRNG(seed: stableSeed(playerID))

        // Position-based weighting: QBs lean Contender/Money; vets lean Family;
        // K/P often Climate. Without age data here we keep it position-agnostic
        // beyond a small bias.
        let allTags = PlayerPreferenceTag.allCases
        guard !allTags.isEmpty else { return [] }

        // Decide whether the player has 1 or 2 preferences (~60% have 2)
        let prefCount = (rng.nextDouble() < 0.6) ? 2 : 1

        // Bias by position
        var weighted: [(PlayerPreferenceTag, Double)] = allTags.map { tag in
            (tag, baseWeight(for: tag, position: position))
        }

        var picks: [PlayerPreferenceTag] = []
        for _ in 0..<prefCount {
            guard let pick = pickWeighted(&weighted, rng: &rng) else { break }
            picks.append(pick)
        }
        return picks
    }

    /// Computes how well a team's situation fits the player's preferences (0...1).
    /// Each preference contributes equally; the score is the average match.
    static func teamFitScore(
        preferences: [PlayerPreferenceTag],
        teamID: UUID,
        teamRecord: (wins: Int, losses: Int)?,
        teamRegion: String?,
        coachReunionAvailable: Bool,
        playerHometown: String?,
        teamRegionForHometown: String?
    ) -> Double {
        guard !preferences.isEmpty else { return 0.5 }

        var total: Double = 0
        for pref in preferences {
            total += matchScore(
                pref: pref,
                teamRecord: teamRecord,
                teamRegion: teamRegion,
                coachReunionAvailable: coachReunionAvailable,
                playerHometown: playerHometown,
                teamRegionForHometown: teamRegionForHometown
            )
        }
        return total / Double(preferences.count)
    }

    /// User-visible offer ranking. Combines bid total value with team-fit score
    /// to give the player's "true preference order" of competing offers.
    static func offerRanking(
        userTeamID: UUID,
        bids: [FABid],
        preferences: [PlayerPreferenceTag],
        teamFits: [UUID: Double]
    ) -> (yourRank: Int, totalOffers: Int) {
        // Aggregate the latest pending/active bid per team (highest annual value).
        let active = bids.filter { $0.status == .pending || $0.status == .countered }
        var bestPerTeam: [UUID: Int] = [:]
        for bid in active {
            let aav = annualValue(of: bid)
            if let existing = bestPerTeam[bid.teamID] {
                if aav > existing { bestPerTeam[bid.teamID] = aav }
            } else {
                bestPerTeam[bid.teamID] = aav
            }
        }

        if bestPerTeam.isEmpty { return (0, 0) }

        // Score each team: 70% money, 30% fit
        let scored: [(teamID: UUID, score: Double)] = bestPerTeam.map { (teamID, aav) in
            let fit = teamFits[teamID] ?? 0.5
            let moneyComponent = Double(aav) / 1000.0  // raw thousands as score basis
            let score = moneyComponent * 0.7 + fit * 5_000 * 0.3
            return (teamID, score)
        }

        let sorted = scored.sorted { $0.score > $1.score }
        let total = sorted.count
        let rank = (sorted.firstIndex(where: { $0.teamID == userTeamID }) ?? -1) + 1
        return (rank, total)
    }

    // MARK: - Private helpers

    private static func annualValue(of bid: FABid) -> Int {
        guard bid.years > 0 else { return bid.baseSalary + bid.signingBonus }
        return bid.baseSalary + (bid.signingBonus / max(bid.years, 1))
    }

    private static func stableSeed(_ uuid: UUID) -> UInt64 {
        var seed: UInt64 = 1469598103934665603 // FNV offset basis
        withUnsafeBytes(of: uuid.uuid) { rawBuf in
            for byte in rawBuf {
                seed ^= UInt64(byte)
                seed &*= 1099511628211 // FNV prime
            }
        }
        return seed
    }

    private static func baseWeight(
        for tag: PlayerPreferenceTag,
        position: Position
    ) -> Double {
        // Light position-bias scaffolding (preferences not coupled to position
        // until full design lands). Adjust here if PlayerPreferenceTag adds cases.
        switch position {
        case .QB:
            return 1.0
        case .K, .P:
            return 1.0
        default:
            return 1.0
        }
    }

    private static func matchScore(
        pref: PlayerPreferenceTag,
        teamRecord: (wins: Int, losses: Int)?,
        teamRegion: String?,
        coachReunionAvailable: Bool,
        playerHometown: String?,
        teamRegionForHometown: String?
    ) -> Double {
        // Match by raw value to avoid hard-coupling to specific cases the parallel
        // agent may rename. Score 0.0 (worst) to 1.0 (perfect fit).
        let raw = pref.rawValueLowercased

        if raw.contains("contend") || raw.contains("winner") {
            guard let rec = teamRecord else { return 0.5 }
            let total = max(rec.wins + rec.losses, 1)
            let pct = Double(rec.wins) / Double(total)
            return min(max(pct, 0.0), 1.0)
        }
        if raw.contains("money") || raw.contains("max") {
            // Money preference is satisfied via the bid value, not team-fit.
            return 0.5
        }
        if raw.contains("family") || raw.contains("home") || raw.contains("hometown") {
            guard let hometown = playerHometown,
                  let region = teamRegionForHometown,
                  !hometown.isEmpty,
                  !region.isEmpty else { return 0.4 }
            return hometown.localizedCaseInsensitiveContains(region) ||
                   region.localizedCaseInsensitiveContains(hometown) ? 1.0 : 0.3
        }
        if raw.contains("climate") || raw.contains("warm") {
            guard let region = teamRegion?.lowercased() else { return 0.5 }
            // South / West warm-climate proxy
            if region.contains("south") || region.contains("west") || region.contains("florida") || region.contains("california") {
                return 1.0
            }
            return 0.3
        }
        if raw.contains("coach") || raw.contains("reunion") {
            return coachReunionAvailable ? 1.0 : 0.3
        }
        if raw.contains("region") {
            guard let r1 = teamRegion, let r2 = teamRegionForHometown else { return 0.5 }
            return r1.caseInsensitiveCompare(r2) == .orderedSame ? 1.0 : 0.3
        }
        // Default: neutral
        return 0.5
    }

    private static func pickWeighted(
        _ pool: inout [(PlayerPreferenceTag, Double)],
        rng: inout SeededRNG
    ) -> PlayerPreferenceTag? {
        let total = pool.reduce(0.0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        let r = rng.nextDouble() * total
        var acc = 0.0
        for (idx, entry) in pool.enumerated() {
            acc += entry.1
            if r <= acc {
                pool.remove(at: idx)
                return entry.0
            }
        }
        let last = pool.removeLast()
        return last.0
    }
}

// MARK: - Tag introspection helper

private extension PlayerPreferenceTag {
    /// Lowercased rawValue, defensive against cases that don't conform to RawRepresentable<String>.
    var rawValueLowercased: String {
        String(describing: self).lowercased()
    }
}

// MARK: - Tiny seeded RNG (not for cryptography)

private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
    mutating func nextDouble() -> Double {
        // 53-bit mantissa
        let v = next() >> 11
        return Double(v) / Double(1 << 53)
    }
}
