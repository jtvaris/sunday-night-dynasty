import Foundation

// MARK: - Game Weather

/// Per-game weather condition. Purely derived — computed deterministically
/// from the game's UUID and week number, so no SwiftData field is needed and
/// every caller (quick sim, live engine, scoreboard, summary) gets the same
/// answer for the same game.
enum GameWeather: String, Codable, CaseIterable {
    case clear
    case rain
    case snow
    case wind

    /// Deterministic weather draw for one game.
    ///
    /// Base distribution: clear 55% / rain 20% / wind 15% / snow 10%.
    /// Late-season weeks (12+) shift odds from clear toward snow — +4
    /// percentage points per week, capped at +20 by week 16 (winter football).
    ///
    /// The roll comes from the UUID's raw bytes, NOT `hashValue` — Hashable's
    /// seed changes every launch, which would re-roll the weather per run.
    static func forGame(id: UUID, week: Int) -> GameWeather {
        let bytes = id.uuid
        var value: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7] {
            value = (value << 8) | UInt64(byte)
        }
        let roll = Int(value % 100)

        let extraSnow = max(0, min(20, (week - 11) * 4))
        let snowCut = 10 + extraSnow    // snow band grows late in the year
        let rainCut = snowCut + 20      // rain band
        let windCut = rainCut + 15      // wind band; the remainder is clear
        switch roll {
        case ..<snowCut: return .snow
        case ..<rainCut: return .rain
        case ..<windCut: return .wind
        default:         return .clear
        }
    }

    // MARK: - UI Helpers

    /// Short display name for scoreboard chips.
    var label: String {
        switch self {
        case .clear: return "Clear"
        case .rain:  return "Rain"
        case .snow:  return "Snow"
        case .wind:  return "Windy"
        }
    }

    /// SF Symbol shown next to the label.
    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .rain:  return "cloud.rain.fill"
        case .snow:  return "snowflake"
        case .wind:  return "wind"
        }
    }
}
