import Foundation

/// Tracks per-player workload accumulation during OTAs / Training Camp.
/// Drives injury risk multipliers and burnout warnings in the UI.
enum WorkloadStatus: String, Codable, CaseIterable {
    case underloaded
    case healthy
    case overloaded
    case burnedOut

    /// The state as a WORD — and the only spelling of it.
    ///
    /// Three screens of the same feature invented three vocabularies: the
    /// training-plan pill said `Light / Healthy / Heavy / Burnt`, the heat-map
    /// legend hardcoded `Under-loaded / Healthy / Over-loaded / Burned out`, and
    /// the workload sheet printed `rawValue.capitalized`, which can only ever
    /// emit "Underloaded" and "Burnedout". A user who learns to watch for
    /// "Burnt" — the word the plan screen's own caption quotes — has to find
    /// that same word one tap away, so the pill's vocabulary is the one that
    /// wins.
    var displayLabel: String {
        switch self {
        case .underloaded: return "Light"
        case .healthy:     return "Healthy"
        case .overloaded:  return "Heavy"
        case .burnedOut:   return "Burnt"
        }
    }

    /// Compact indicator for dashboards / heat-maps.
    ///
    /// This was an `emoji` — 🔥 and 💀 — which UI_REDESIGN_VISION §2.12 rules
    /// out by name and which VoiceOver speaks as "fire" and "skull". It also
    /// left `.underloaded` on a bare ASCII hyphen: one of the four states had
    /// opted out of the glyph system entirely, so 45 of 53 heat-map cells were
    /// a dash that nothing on the screen defined.
    var symbolName: String {
        switch self {
        case .underloaded: return "arrow.down.circle"
        case .healthy:     return "checkmark.circle.fill"
        case .overloaded:  return "flame.fill"
        case .burnedOut:   return "exclamationmark.triangle.fill"
        }
    }

    /// Multiplier applied to the player's base injury probability while in this state.
    var injuryMultiplier: Double {
        switch self {
        case .underloaded: return 1.0
        case .healthy:     return 1.0
        case .overloaded:  return 1.6
        case .burnedOut:   return 2.5
        }
    }

    /// Whether this state costs the player anything on top of his own
    /// durability.
    ///
    /// `.underloaded` and `.healthy` both multiply by 1.0 and `.underloaded` is
    /// branched on nowhere else in the engine (`TrainingPlanEngine` tests only
    /// `== .burnedOut`), so the two grey-vs-green bands a heat-map draws carry
    /// identical consequences today. A screen that says "at risk" has to count
    /// the states that actually are, rather than implying four tiers of danger.
    var addsInjuryRisk: Bool { injuryMultiplier > 1.0 }
}

/// Aggregate camp evaluation grade. Surfaces in roster cut UI and Hard Knocks events.
enum CampGrade: String, Codable, CaseIterable {
    case aPlus
    case a
    case b
    case c
    case d
    case f

    /// Display label as letters (A+, A, B, …) — never numeric per project design.
    var displayLabel: String {
        switch self {
        case .aPlus: return "A+"
        case .a:     return "A"
        case .b:     return "B"
        case .c:     return "C"
        case .d:     return "D"
        case .f:     return "F"
        }
    }

    /// Best-to-worst ordering, high is good.
    ///
    /// `allCases` already happens to be in that order, but a screen that has to
    /// say "better than 31 of 48 graded team-mates" needs to compare two grades,
    /// not trust the index of a case in a list anyone is free to reorder.
    var rank: Int {
        switch self {
        case .aPlus: return 5
        case .a:     return 4
        case .b:     return 3
        case .c:     return 2
        case .d:     return 1
        case .f:     return 0
        }
    }
}

/// Roster cut day stage. The 90-man roster is trimmed in three stages
/// before the regular season opener.
enum CutDay: String, Codable, CaseIterable {
    case cut90To75
    case cut75To65
    case cut65To53
}

/// Type of voluntary / mandatory team workout requested by the GM.
/// Each type has different participation, scheme bonus, and locker-room implications.
enum VoluntaryWorkoutType: String, Codable, CaseIterable {
    case voluntaryOTAs
    case mandatoryMinicamp
    case saturdayFilm
    case offDayPractice
}

/// Hard Knocks-style narrative event surfaced during camp.
enum HardKnocksEventType: String, Codable, CaseIterable {
    case rookieBreakout
    case vetOnBubble
    case surpriseStarter
    case depthChartShakeup
    case campInjury
    case tradeRumor
}
