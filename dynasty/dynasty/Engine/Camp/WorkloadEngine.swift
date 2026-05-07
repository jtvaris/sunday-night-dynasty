import Foundation
import SwiftData

// MARK: - WorkloadEngine

/// Tracks per-player camp workload, classifies status (underloaded/healthy/overloaded/burnedOut),
/// and converts that into a daily injury-risk multiplier. Driven daily by the camp scheduler;
/// stays consistent across OTAs, full-pads camp, and preseason snaps.
@MainActor
enum WorkloadEngine {

    // MARK: - Constants

    /// Cumulative-load thresholds (matched to design heuristic).
    private static let underloadedMax = 30
    private static let healthyMax = 80
    private static let overloadedMax = 130

    /// Loose cap so cumulativeLoad cannot grow unbounded across many weeks.
    private static let absoluteCap = 200

    // MARK: - Public API

    /// Updates a player's `cumulativeLoad` given today's training intensity (0..1)
    /// and the strength coach's recovery rate (0..1).
    /// Persists a `WorkloadEvent` row for the day.
    static func tickDay(
        player: Player,
        intensity: Double,
        recoveryRate: Double,
        modelContext: ModelContext
    ) {
        let clampedIntensity = max(0.0, min(1.0, intensity))
        let clampedRecovery = max(0.0, min(1.0, recoveryRate))

        // Load delta scales 0..18 per day at full intensity. Stamina partly absorbs load.
        let staminaFactor = 1.0 - (Double(player.physical.stamina) / 99.0) * 0.4
        let loadDelta = Int((clampedIntensity * 18.0 * staminaFactor).rounded())

        // Recovery delta scales 0..10 per day. Trainer skill amplifies recovery.
        let recoveryDelta = Int((clampedRecovery * 10.0).rounded())

        let net = loadDelta - recoveryDelta
        let newLoad = max(0, min(absoluteCap, player.cumulativeLoad + net))
        player.cumulativeLoad = newLoad
        player.workloadStatus = classify(load: newLoad)

        let event = WorkloadEvent(
            playerID: player.id,
            seasonYear: Calendar.current.component(.year, from: .now),
            dayOfWeek: Calendar.current.component(.weekday, from: .now) - 1,
            loadDelta: loadDelta,
            recoveryDelta: recoveryDelta
        )
        modelContext.insert(event)
    }

    /// Classifies workload status from `cumulativeLoad` thresholds.
    static func classify(load: Int) -> WorkloadStatus {
        switch load {
        case ..<underloadedMax:                 return .underloaded
        case underloadedMax..<healthyMax:       return .healthy
        case healthyMax..<overloadedMax:        return .overloaded
        default:                                 return .burnedOut
        }
    }

    /// Returns daily injury risk percentage (0..100) for a player given their workload
    /// status + base risk (0..1). Stacks the status multiplier on top of the player's
    /// inherent durability factor.
    static func injuryRiskPct(player: Player, baseRisk: Double) -> Double {
        let status = player.workloadStatus
        let durabilityFactor = (99.0 - Double(player.physical.durability)) / 99.0 * 0.4 + 1.0
        let combined = baseRisk * status.injuryMultiplier * durabilityFactor
        return min(100.0, combined * 100.0)
    }
}
