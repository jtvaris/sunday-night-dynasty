import Foundation

/// Tracks per-player workload accumulation during OTAs / Training Camp.
/// Drives injury risk multipliers and burnout warnings in the UI.
enum WorkloadStatus: String, Codable, CaseIterable {
    case underloaded
    case healthy
    case overloaded
    case burnedOut

    /// Compact emoji indicator for dashboards / heat-maps.
    var emoji: String {
        switch self {
        case .underloaded: return "-"
        case .healthy:     return "✓"
        case .overloaded:  return "🔥"
        case .burnedOut:   return "💀"
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
