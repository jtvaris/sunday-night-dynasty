import Foundation

// MARK: - CampGradeEvaluator

/// Aggregates per-player camp evaluation into a single `CampGrade` letter.
/// Combines accumulated training points (from `TrainingPlanEngine`) with
/// preseason snap volume × performance quality. Output is a letter grade
/// (A+, A, B, …) — never a numeric score, per project design.
enum CampGradeEvaluator {

    // MARK: - Public API

    /// Computes a camp grade for a player from training + preseason snap quality.
    /// Uses weekly training pts + preseason snaps × performance factor.
    static func computeGrade(
        player: Player,
        trainingPts: Int,
        preseasonSnaps: Int,
        preseasonAvgPerf: Double
    ) -> CampGrade {
        let score = scoreFor(
            player: player,
            trainingPts: trainingPts,
            preseasonSnaps: preseasonSnaps,
            preseasonAvgPerf: preseasonAvgPerf
        )
        return gradeFor(score: score)
    }

    /// Returns numeric score (0..100) used internally to bucket into a grade letter.
    /// Exposed so the UI can sort players within the same letter grade.
    static func scoreFor(
        player: Player,
        trainingPts: Int,
        preseasonSnaps: Int,
        preseasonAvgPerf: Double
    ) -> Int {
        // --- Training contribution (0..40) ---
        // Cap training pts at ~30 per camp to normalize across phases.
        let trainingScore = min(40, Int(Double(min(trainingPts, 30)) / 30.0 * 40.0))

        // --- Preseason snap volume (0..25) ---
        // 80+ snaps over 3 preseason games is generous — cap there.
        let snapScore = min(25, Int(Double(min(preseasonSnaps, 80)) / 80.0 * 25.0))

        // --- Preseason performance quality (0..25) ---
        // 0..1 input — just multiplied through.
        let perfScore = min(25, Int(max(0.0, min(1.0, preseasonAvgPerf)) * 25.0))

        // --- Floor from raw OVR (0..10) ---
        // Stars don't fall to D unless they bombed camp; rooks need to earn it.
        let ovr = player.overall
        let ovrFloor = ovr >= 80 ? 10 : (ovr >= 70 ? 7 : (ovr >= 60 ? 4 : 0))

        let total = trainingScore + snapScore + perfScore + ovrFloor

        // Holdout / injured players take a hit (no preseason participation).
        if player.isInjured {
            return max(0, total - 12)
        }
        return min(100, max(0, total))
    }

    // MARK: - Private Helpers

    private static func gradeFor(score: Int) -> CampGrade {
        switch score {
        case 90...:  return .aPlus
        case 80..<90: return .a
        case 65..<80: return .b
        case 50..<65: return .c
        case 35..<50: return .d
        default:      return .f
        }
    }
}
