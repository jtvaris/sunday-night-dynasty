import Foundation
import SwiftData

// MARK: - RosterCutEvaluator

/// Recommends which players to cut for each of the three roster trim days
/// (90→75, 75→65, 65→53). Considers camp grade, OVR, age, contract, and
/// position-group depth. Surfaces practice-squad eligibility and per-cut
/// cap savings / dead cap impact.
@MainActor
enum RosterCutEvaluator {

    // MARK: - Public API

    /// Recommends cut candidates ordered worst-first.
    /// - Parameters:
    ///   - roster: Full team roster (90 / 75 / 65 player array).
    ///   - targetCount: Roster size to trim down to (75 / 65 / 53).
    ///   - modelContext: SwiftData context (used for contract lookups when present).
    /// - Returns: Array of `Player` objects in order of cut priority.
    static func recommendCuts(
        roster: [Player],
        targetCount: Int,
        modelContext: ModelContext
    ) -> [Player] {
        guard roster.count > targetCount else { return [] }

        let cutCount = roster.count - targetCount

        // Score each player on a "keep" axis. Lower score → higher cut priority.
        let scored: [(player: Player, keepScore: Double)] = roster.map { p in
            (player: p, keepScore: keepScore(for: p))
        }

        // Sort ascending by keepScore (worst first).
        let sorted = scored.sorted { $0.keepScore < $1.keepScore }

        // Apply a soft "preserve depth at thin positions" filter:
        // never cut so deep that a position group falls below 1.
        var planned: [Player] = []
        var remainingByPosition: [Position: Int] = [:]
        for p in roster {
            remainingByPosition[p.position, default: 0] += 1
        }

        for entry in sorted {
            guard planned.count < cutCount else { break }
            let pos = entry.player.position
            let remaining = remainingByPosition[pos] ?? 0
            // Never thin a position to below 1 — the UI can let the GM override.
            if remaining <= 1 { continue }
            planned.append(entry.player)
            remainingByPosition[pos] = remaining - 1
        }

        // If depth-protection blocked us from reaching cutCount, fall back to raw worst.
        if planned.count < cutCount {
            for entry in sorted where !planned.contains(where: { $0.id == entry.player.id }) {
                planned.append(entry.player)
                if planned.count >= cutCount { break }
            }
        }

        return planned
    }

    /// Cap savings if player is cut (in thousands).
    /// Falls back to `annualSalary - deadCap(player)` when no detailed contract is available.
    static func capSavings(player: Player) -> Int {
        let dead = deadCap(player: player)
        return max(0, player.annualSalary - dead)
    }

    /// Dead cap incurred (in thousands) — prorated bonus acceleration if cut now.
    /// In the absence of a Contract row, uses a heuristic based on years remaining.
    static func deadCap(player: Player) -> Int {
        let years = max(0, player.contractYearsRemaining)
        guard years > 0 else { return 0 }

        // Heuristic: 15% of annual salary × remaining years (proxy for prorated bonus).
        let bonusEstimate = Int(Double(player.annualSalary) * 0.15) * years
        return bonusEstimate
    }

    /// Practice-squad eligible? (rookie or <2 accrued seasons.)
    static func isPracticeSquadEligible(player: Player) -> Bool {
        return player.yearsPro <= 2
    }

    // MARK: - Private Helpers

    /// Composite "keep this player" score. Higher = safer; lower = closer to cut block.
    private static func keepScore(for player: Player) -> Double {
        // OVR contribution (0..50)
        let ovrScore = Double(player.overall) * 0.55

        // Camp grade contribution (-10..+15) — graded camp earns a small uplift.
        let gradeScore: Double
        switch player.campGrade {
        case .aPlus: gradeScore = 18.0
        case .a:     gradeScore = 12.0
        case .b:     gradeScore = 5.0
        case .c:     gradeScore = -2.0
        case .d:     gradeScore = -8.0
        case .f:     gradeScore = -12.0
        case nil:    gradeScore = 0.0
        }

        // Age penalty (older = lower keep score for borderline OVRs).
        let agePenalty: Double = {
            switch player.age {
            case ..<25:   return 4.0
            case 25..<29: return 2.0
            case 29..<32: return 0.0
            case 32..<35: return -3.0
            default:      return -7.0
            }
        }()

        // Contract pressure: large salary / high dead-cap → harder to cut.
        // We INVERT this — high salary REDUCES keepScore so big-money under-performers float to the top.
        // BUT a large dead-cap penalty pulls them back as "expensive to release".
        let salaryPenalty = -Double(player.annualSalary) / 5000.0   // -1 per $5M
        let deadCapShield = Double(deadCap(player: player)) / 4000.0 // +1 per $4M dead

        // Injury status drags keep score (you don't keep an injured #80 over a healthy #78).
        let injuryPenalty: Double = player.isInjured ? -6.0 : 0.0

        // Hold-out drama drag — defaults to 0; UI can lift this via personality archetype.
        let dramaPenalty: Double = player.personality.archetype == .dramaQueen ? -3.0 : 0.0

        return ovrScore + gradeScore + agePenalty + salaryPenalty + deadCapShield + injuryPenalty + dramaPenalty
    }
}
