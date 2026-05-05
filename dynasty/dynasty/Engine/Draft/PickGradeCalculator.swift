import Foundation

/// Computes the public-facing draft pick grade from visible signals.
/// See `docs/plans/2026-05-05-draft-day-design.md` §5.
enum PickGradeCalculator {

    /// Inputs visible to fans/media at the moment a pick is made.
    struct Inputs {
        /// BB rank − pick number. Positive = picked later than expected (steal).
        let valueDelta: Int
        /// Need fit, 0..1 (1 = top need).
        let needScore: Double
        /// Public OVR estimate, 40..99.
        let publicOVR: Int
        /// Scheme fit, 0..1.
        let schemeFit: Double
    }

    /// Output of the grade computation.
    struct Output {
        let grade: PickGrade
        /// Composite score, 0..1. Internal — used only for tie-breaks/diagnostics.
        let compositeScore: Double
        /// `true` when the pick qualifies for the instant Steal banner.
        let isGemCandidate: Bool
    }

    /// Computes the grade letter and composite score from the visible inputs.
    static func compute(_ inputs: Inputs) -> Output {
        let composite = compositeScore(inputs)
        let grade = letterGrade(from: inputs)
        let isGem = inputs.valueDelta >= 6 && inputs.needScore >= 0.7
        return Output(grade: grade, compositeScore: composite, isGemCandidate: isGem)
    }

    // MARK: - Private

    /// Weighted composite of the four visible signals — kept internal for diagnostics.
    /// Weights: Value Δ 30%, Need 25%, Public OVR 30%, Scheme 15%.
    private static func compositeScore(_ inputs: Inputs) -> Double {
        let valueComponent = normalizeValueDelta(inputs.valueDelta)   // 0..1
        let needComponent = clamp01(inputs.needScore)
        let ovrComponent = normalizeOVR(inputs.publicOVR)             // 0..1
        let schemeComponent = clamp01(inputs.schemeFit)

        let weighted =
            valueComponent  * 0.30 +
            needComponent   * 0.25 +
            ovrComponent    * 0.30 +
            schemeComponent * 0.15
        return clamp01(weighted)
    }

    /// Letter mapping per Design §5. Order matters — checked top-down.
    private static func letterGrade(from inputs: Inputs) -> PickGrade {
        // A+ Steal
        if inputs.valueDelta >= 6 && inputs.needScore >= 0.6 {
            return .stealAPlus
        }
        // D Big Reach (check before C so it wins when both fire)
        if inputs.valueDelta <= -10 && inputs.needScore <= 0.3 {
            return .bigReach
        }
        // C Reach
        if inputs.valueDelta <= -6 || inputs.needScore <= 0.3 {
            return .reach
        }
        // A Smart Pick
        if inputs.valueDelta >= 0 && inputs.needScore >= 0.5 && inputs.publicOVR >= 75 {
            return .smartA
        }
        // B Solid
        if inputs.valueDelta >= -3 {
            return .solid
        }
        // Fallback for the gap between -6 and -3 with no other trigger.
        return .reach
    }

    /// Maps a value delta in roughly [-30, +30] to 0..1.
    private static func normalizeValueDelta(_ delta: Int) -> Double {
        let clamped = max(-30.0, min(30.0, Double(delta)))
        return (clamped + 30.0) / 60.0
    }

    /// Maps an OVR in [40, 99] to 0..1.
    private static func normalizeOVR(_ ovr: Int) -> Double {
        let clamped = max(40.0, min(99.0, Double(ovr)))
        return (clamped - 40.0) / 59.0
    }

    private static func clamp01(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }
}
