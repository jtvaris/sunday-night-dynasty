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

// MARK: - Contract & Incentive Link (TODO §5.5)

extension MotivationState {

    /// The §2.3 trigger table's contribution from **money still on the table**.
    ///
    /// The table already has a contract-year bump (trigger 5: `+1`, gated on
    /// `PlayerDevelopmentEngine.contractYearGate`). This is its sibling for the
    /// other way a season can be worth money to a player — a live incentive
    /// clause he has not banked yet.
    ///
    /// **It is +1, and it stays +1.** Stacked on the contract-year trigger the
    /// contract-driven half of the table tops out at `+2`, which is exactly the
    /// `.driven` threshold: a contract can therefore tip a player over the line
    /// on its own, but only when nothing else about his season is negative. That
    /// is the ceiling `DEVELOPMENT_NFL_REFERENCE.md` §3 asks for — the
    /// contract-year effect ranges from "myth" to about +5 % in the literature,
    /// so it is allowed to matter and not allowed to be a superpower.
    ///
    /// Gated the same way trigger 5 is: a player at or below the checked-out
    /// line is not chasing anything, and a money-motivated player chases
    /// regardless of how competitive he is.
    ///
    /// WIRED: `PlayerDevelopmentEngine.evaluateMotivation` calls this as
    /// trigger 5b, immediately after the contract-year trigger.
    static func incentiveChaseScore(for player: Player) -> Int {
        guard !ContractIncentiveRegistry.incentives(for: player).isEmpty else { return 0 }
        let chases = player.competitiveness >= PlayerDevelopmentEngine.contractYearGate
            || player.personality.motivation == .money
        return chases ? 1 : 0
    }

    /// One line for the contract card explaining what the clauses are doing to
    /// his head — or `nil` when they are doing nothing.
    ///
    /// Deliberately worded as a description of his SITUATION rather than as a
    /// promised "+1", because the size of the effect is the trigger table's to
    /// decide and the caller cannot know whether the table has been given
    /// ``incentiveChaseScore`` yet. The copy reads true either way.
    static func incentiveChaseNote(for player: Player) -> String? {
        let clauses = ContractIncentiveRegistry.incentives(for: player)
        guard !clauses.isEmpty else { return nil }
        let noun = clauses.count == 1 ? "clause" : "clauses"
        guard incentiveChaseScore(for: player) > 0 else {
            return "Carrying \(clauses.count) \(noun), but he isn't the type to chase them."
        }
        return player.contractYearsRemaining <= 1
            ? "Contract year and \(clauses.count) live \(noun) — he is playing for everything this season."
            : "Chasing \(clauses.count) live \(noun) this season."
    }
}
