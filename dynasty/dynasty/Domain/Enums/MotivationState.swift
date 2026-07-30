import Foundation

// MARK: - Motivation State (Phase 2 — Realization Model §2.3)

/// Where a player's head is at going into the season, recomputed once per
/// offseason when the league enters `.trainingCamp`.
///
/// The state is the *visible* half of the realization model
/// (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.3): it is derived from things
/// that actually happened — a collapsed team season, a down year, a demotion, a
/// contract year, a fresh payday — gated by the player's `competitiveness`, and
/// it then multiplies **training output** (offseason development points, the
/// weekly focus tick, the R factor) and nudges morale. It never touches game
/// ratings directly, per `docs/DEVELOPMENT_NFL_REFERENCE.md` §4.
///
/// Stored on `Player.motivationStateRaw` as a raw string with a nil default, so
/// existing saves migrate lightweight and read as `.focused` until their first
/// camp under the new engine.
enum MotivationState: String, Codable, CaseIterable, Identifiable {
    /// Chip on the shoulder — best shape of his life. Adversity answered.
    case driven
    /// The league-average headspace: professional, unremarkable. The default.
    case focused
    /// Post-payday coast. Only reachable through the "just paid" trigger.
    case complacent
    /// Checked out — a bad situation he is not fighting.
    case discouraged

    var id: String { rawValue }

    /// The state a player is in when nothing has ever been computed for him
    /// (legacy save rows, players created mid-cycle). Deliberately the neutral
    /// state so an unwritten row develops exactly as it did before phase 2.
    static let `default`: MotivationState = .focused

    // MARK: - Display

    var displayName: String {
        switch self {
        case .driven:      return String(localized: "Driven")
        case .focused:     return String(localized: "Focused")
        case .complacent:  return String(localized: "Complacent")
        case .discouraged: return String(localized: "Discouraged")
        }
    }

    /// SF Symbol for badges and development-report rows.
    var icon: String {
        switch self {
        case .driven:      return "flame.fill"
        case .focused:     return "scope"
        case .complacent:  return "zzz"
        case .discouraged: return "cloud.rain.fill"
        }
    }

    /// One-line explanation surfaced next to the badge.
    var summary: String {
        switch self {
        case .driven:
            return String(localized: "Showed up with something to prove — training output is up.")
        case .focused:
            return String(localized: "Business as usual in the building.")
        case .complacent:
            return String(localized: "Got paid and eased off — the work has slipped.")
        case .discouraged:
            return String(localized: "His head isn't in it. Development has stalled.")
        }
    }

    // MARK: - Tuning (plan §2.3)

    /// Multiplier on offseason development points and on the R factor.
    var developmentMultiplier: Double {
        switch self {
        case .driven:      return 1.30
        case .focused:     return 1.00
        case .complacent:  return 0.75
        case .discouraged: return 0.60
        }
    }

    /// One-off morale nudge applied when the state is assigned at camp.
    var moraleDelta: Int {
        switch self {
        case .driven:      return 3
        case .focused:     return 0
        case .complacent:  return -1
        case .discouraged: return -3
        }
    }

    /// Multiplier on `TrainingFocusEngine.weeklyGainChance`. Composes with the
    /// existing morale factor; the 0.6 hard cap is unchanged.
    var focusGainMultiplier: Double {
        switch self {
        case .driven:      return 1.20
        case .focused:     return 1.00
        case .complacent:  return 0.85
        case .discouraged: return 0.70
        }
    }

    // MARK: - Score Mapping

    /// Maps the §2.3 trigger score onto a state.
    ///
    /// `≥ +2` driven · `+1…−1` focused · `≤ −2` discouraged — except that a
    /// negative score **dominated by the post-payday trigger** reads as
    /// `.complacent` rather than `.discouraged`. The distinction matters
    /// narratively (a coasting star is not a broken one) and mechanically
    /// (0.75 vs 0.60 output).
    ///
    /// - Parameters:
    ///   - score: Sum of every trigger's contribution.
    ///   - paydayPenalty: The (negative) contribution of the "just paid"
    ///     trigger alone, `0` when it did not fire.
    ///   - otherPenalty: The summed contribution of every OTHER negative
    ///     trigger. The payday is "dominant" when it is at least as heavy as
    ///     all of them put together.
    static func from(score: Int, paydayPenalty: Int, otherPenalty: Int) -> MotivationState {
        if score >= 2 { return .driven }
        if score >= -1 { return .focused }
        if paydayPenalty < 0 && paydayPenalty <= otherPenalty { return .complacent }
        return .discouraged
    }
}
