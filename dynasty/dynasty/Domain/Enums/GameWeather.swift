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
    /// Indoor game: a fixed-roof dome, or a retractable-roof stadium whose
    /// roof closes against bad weather. Plays exactly like `.clear` for the
    /// simulator (every weather branch treats it as no-op / default) — it
    /// exists only so the UI can badge the game "DOME" and the 3D field can
    /// skip precipitation.
    case dome

    // MARK: - Venue Lookup (static — no SwiftData field)

    /// Home teams that play under a permanent fixed roof: no weather, ever.
    private static let fixedDomeTeams: Set<String> = [
        "ATL", "NO", "DET", "MIN", "LV", "LAR", "LAC",
    ]

    /// Home teams with a retractable roof. The roof closes for bad weather,
    /// so these venues never see rain/snow/wind at home — but stay open
    /// (plain `.clear`) on a fair-weather day.
    private static let retractableRoofTeams: Set<String> = [
        "DAL", "HOU", "IND", "ARI",
    ]

    /// True when the home venue is (or can be closed into) an indoor stadium —
    /// i.e. bad weather can never reach the field.
    static func isDomeVenue(_ abbreviation: String) -> Bool {
        fixedDomeTeams.contains(abbreviation) || retractableRoofTeams.contains(abbreviation)
    }

    /// Deterministic weather draw for one game.
    ///
    /// Base distribution: clear 55% / rain 20% / wind 15% / snow 10%.
    /// Late-season weeks (12+) shift odds from clear toward snow — +4
    /// percentage points per week, capped at +20 by week 16 (winter football).
    ///
    /// The roll comes from the UUID's raw bytes, NOT `hashValue` — Hashable's
    /// seed changes every launch, which would re-roll the weather per run.
    ///
    /// - Parameter homeTeamAbbreviation: the home franchise's abbreviation.
    ///   Fixed-roof domes always return `.dome`; retractable-roof venues
    ///   return `.dome` only when the base draw would have been bad weather
    ///   (the roof closes). Passing `nil` preserves the pure outdoor draw.
    ///   Every caller (quick sim, live engine, summary) must pass the same
    ///   value so both paths agree on one deterministic result.
    static func forGame(id: UUID, week: Int, homeTeamAbbreviation: String? = nil) -> GameWeather {
        // Fixed roof: indoors regardless of the calendar or the draw.
        if let abbr = homeTeamAbbreviation, fixedDomeTeams.contains(abbr) {
            return .dome
        }

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
        let base: GameWeather
        switch roll {
        case ..<snowCut: base = .snow
        case ..<rainCut: base = .rain
        case ..<windCut: base = .wind
        default:         base = .clear
        }

        // Retractable roof: closes only against bad weather, so a nice day
        // stays open-air `.clear` while rain/snow/wind becomes an indoor game.
        if base != .clear,
           let abbr = homeTeamAbbreviation,
           retractableRoofTeams.contains(abbr) {
            return .dome
        }
        return base
    }

    // MARK: - UI Helpers

    /// Short display name for scoreboard chips.
    var label: String {
        switch self {
        case .clear: return "Clear"
        case .rain:  return "Rain"
        case .snow:  return "Snow"
        case .wind:  return "Windy"
        case .dome:  return "Dome"
        }
    }

    /// SF Symbol shown next to the label.
    var symbolName: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .rain:  return "cloud.rain.fill"
        case .snow:  return "snowflake"
        case .wind:  return "wind"
        case .dome:  return "building.columns.fill"
        }
    }
}
