import Foundation

/// A plain Codable value type that stores coaching philosophy sliders for a single game or season.
/// All values are normalised to the [0.0, 1.0] range.
nonisolated struct GamePlan: Codable, Equatable {

    // MARK: - Settings

    /// How aggressively the offense plays (0 = conservative, 1 = aggressive).
    var offensiveAggression: Double

    /// How aggressively the defense plays (0 = conservative, 1 = aggressive).
    var defensiveAggression: Double

    /// Mix of run vs. pass (0 = all run, 1 = all pass).
    var runPassRatio: Double

    /// How often the defense sends extra rushers (0 = never, 1 = always).
    var blitzFrequency: Double

    /// Willingness to go for it on fourth down (0 = always punt, 1 = always go for it).
    var fourthDownAggressiveness: Double

    // MARK: - Presets

    /// All sliders at 0.5 — a neutral, balanced game plan.
    static var balanced: GamePlan {
        GamePlan(
            offensiveAggression: 0.5,
            defensiveAggression: 0.5,
            runPassRatio: 0.5,
            blitzFrequency: 0.5,
            fourthDownAggressiveness: 0.5
        )
    }

    /// Low-risk, ball-control style.
    static var conservative: GamePlan {
        GamePlan(
            offensiveAggression: 0.15,
            defensiveAggression: 0.2,
            runPassRatio: 0.25,
            blitzFrequency: 0.15,
            fourthDownAggressiveness: 0.1
        )
    }

    /// High-risk, high-reward style designed to swing the game.
    static var aggressive: GamePlan {
        GamePlan(
            offensiveAggression: 0.85,
            defensiveAggression: 0.8,
            runPassRatio: 0.75,
            blitzFrequency: 0.8,
            fourthDownAggressiveness: 0.9
        )
    }

    // MARK: - Helpers

    /// True when every slider matches `other` within the given tolerance.
    /// Used by the UI to highlight the currently active preset.
    func matches(_ other: GamePlan, tolerance: Double = 0.01) -> Bool {
        abs(offensiveAggression - other.offensiveAggression) <= tolerance
            && abs(defensiveAggression - other.defensiveAggression) <= tolerance
            && abs(runPassRatio - other.runPassRatio) <= tolerance
            && abs(blitzFrequency - other.blitzFrequency) <= tolerance
            && abs(fourthDownAggressiveness - other.fourthDownAggressiveness) <= tolerance
    }

    /// Human-readable summary of the game plan's overall character.
    var styleSummary: String {
        let avg = (offensiveAggression + defensiveAggression + blitzFrequency + fourthDownAggressiveness) / 4.0
        switch avg {
        case 0.0..<0.3:  return "Conservative"
        case 0.3..<0.55: return "Balanced"
        case 0.55..<0.75: return "Aggressive"
        default:         return "All-Out Attack"
        }
    }

    /// Human-readable label for the run-pass split.
    var runPassLabel: String {
        switch runPassRatio {
        case 0.0..<0.25: return "Heavy Run"
        case 0.25..<0.45: return "Run-First"
        case 0.45..<0.55: return "Balanced"
        case 0.55..<0.75: return "Pass-First"
        default:          return "Heavy Pass"
        }
    }
}

// MARK: - Opponent prep (D1 / F-15 / F-16)

/// What a week of preparation is worth, on the scale the play-by-play simulator
/// actually consumes.
///
/// # Why this type exists at all
///
/// Opponent prep used to be applied AFTER the whistle, as a multiplier on the
/// final score: `×1.10` on the user's points and `×0.925` on the rival's
/// (`GameSimulator` §6b, deleted with this type). At an engine-typical 24 points
/// a side that is **+4.2 points of margin every regular-season game**, which
/// against an NFL margin sd of 13.5 turns a coin flip into 62.2 % — **8.5 → 10.6
/// wins, +2.1 wins a season**. It was also user-only: `OpponentPrepWeek`'s single
/// construction site hard-codes the career's own club, so no AI team has ever had
/// a row. D1's ruling is three-part and this type is all three of them:
///
/// 1. **Thread it.** Prep is now a `PlaySimulator.Adjustments` delta composed
///    into the same channel the coaching staff already moves — completion
///    probability and rushing yardage, per play, on the snaps it should affect.
///    Nothing edits a score after the fact any more.
/// 2. **Share it.** Every club has a `focus`, derived from the staff it already
///    employs (`CoachingModifiers.TeamRatings.gamePlanning`, computed once per
///    game and free at this call site). The user's slider is a DELTA on top of
///    his own staff's number, not a private channel.
/// 3. **Shrink it.** Calibrated by measurement, not by taste. Harness cell
///    `fullgame --home-tier 80 --away-tier 78 --n 20000`, slider at 100 % vs at
///    50 %: home margin **+6.1 vs +5.3**, i.e. a maximum-prep week against an
///    average staff is worth **+0.8 points of margin** (SE ≈0.11) — **19 % of
///    the +4.2 it was**. The argument that decides the size is the one that is
///    not negotiable: the best-to-worst head-coach spread in the real league is
///    ≈1.5-2.5 wins IN TOTAL, so a prep slider worth +2.1 on its own was worth
///    more than an entire coach.
///
/// # The scale, and why 0.5 is the middle
///
/// `focus` runs 0…1 and **0.5 is the league-average week**, not zero. Prep is a
/// contest, not a bonus: the modifier is `focus − 0.5`, so a club with a poor
/// planner is preparing WORSE than the league and is measurably hurt by it, and
/// two average staffs cancel exactly. A user who never touches the Week Prep
/// screen sits where his staff sits, which is the honest answer to "what happens
/// if I ignore this?".
///
/// A `nil` staff (no coaches — every harness roster, and any club mid-migration)
/// reads as exactly 0.5 and therefore contributes exactly nothing, so the
/// shipped balance-harness `fullgame` numbers are byte-comparable across this
/// change. That parity is the F-16 verification condition.
///
/// # What was tried and rejected
///
/// * **Keeping the post-hoc multiplier at a fifth of its size.** Cheaper, and
///   still a scoreboard edit — a 3-yard prep advantage that manifests as points
///   the drive chart cannot explain. The audits call this the injury-system bug
///   class in mirror image and the ruling calls it "the one edge with no defence".
/// * **A new stored `prepRating` on `Team` or `Coach`.** A schema migration to
///   store a number the staff already implies. `gamePlanning` IS this attribute;
///   inventing a second one would let the two disagree.
/// * **Deriving the AI's focus from its RECORD.** Cheap and circular: prep would
///   then help the clubs already winning, which is the D4 freeze in miniature.
///
/// # The known double-count, stated rather than hidden
///
/// `gamePlanning` also drives `CoachingModifiers` mechanic 2 (±0.018 completion,
/// ±0.18 ypc per planner). Prep reads the same attribute on purpose — game
/// planning and opponent prep are the same real-world thing at two timescales,
/// and splitting them across two attributes would have meant inventing one. The
/// combined slope is still bounded well under a head coach's real worth: mech 2
/// plus prep over the full 40→100 attribute spread is ≈2.5 points of margin,
/// ≈1.25 wins, against the 1.5-2.5 the whole job is worth.
nonisolated enum OpponentPrep {

    // MARK: Scale

    /// The league-average week. Every modifier below is measured from here.
    static let neutralFocus: Double = 0.5

    /// Attribute points of `gamePlanning` that span the whole 0…1 focus scale.
    /// 60 puts grade 40 at focus 0.0, grade 70 (the `CoachingModifiers` neutral
    /// pivot) at 0.5, and grade 100 at 1.0 — the natural span of the attribute
    /// rather than a tuned window.
    static let staffSpan: Double = 60.0

    // MARK: Magnitude

    /// Completion probability the OWN offense gains at maximum focus
    /// (`focus − 0.5 = +0.5`). The audible half of the old `0.20` boost.
    ///
    /// The four spans below were fitted, not chosen: the first pass ran
    /// 0.030 / 0.22 / 0.0225 / 0.165 and measured **+3.3 points of margin**, so
    /// they were scaled by the measured ratio until the cell read +0.8. Anyone
    /// re-tuning them should re-run the same two cells rather than reasoning
    /// about the completion number in isolation — the run and pass halves
    /// interact through the play mix.
    static let audibleCompletionSpan: Double = 0.0060
    /// Rushing yards per carry the own offense gains at maximum focus.
    static let audibleRunSpan: Double = 0.045
    /// Completion probability the OPPONENT'S offense loses at maximum focus.
    /// Three-quarters of the audible span, preserving the original design's
    /// 20 : 15 offense-to-defense ratio.
    static let readCompletionSpan: Double = 0.0045
    /// Rushing yards per carry the opponent's offense loses at maximum focus.
    static let readRunSpan: Double = 0.034

    /// Focus given back for each consecutive week past the second spent at 70 %+
    /// opponent-specific prep — F-15's counterweight, in a channel the simulator
    /// reads.
    ///
    /// The penalty used to be `−1…−3` on `physical.stamina`, and `stamina` has
    /// **zero occurrences** in `PlaySimulator`, `GameSimulator`, `DriveSimulator`,
    /// `LiveGameEngine` or `SimPlayer`. Its only engine consumer feeds a
    /// camp-time constant. Measured cost of riding it to the floor for a whole
    /// season: **−1.5 displayed OVR and exactly zero simulator effect.** Routing
    /// it here makes the slider a real trade — three straight opponent-heavy
    /// weeks hand back 0.30 of focus, which is 60 % of the maximum edge — and it
    /// lands in the one channel prep now lives in, so it cannot rot the same way
    /// twice.
    static let driftFocusPerWeek: Double = 0.10

    // MARK: API

    /// Where a club's staff prepares, before anything its coaches are told to do
    /// this particular week. `nil` (no staff on file) is exactly neutral.
    static func staffFocus(gamePlanning: Double?) -> Double {
        guard let g = gamePlanning else { return neutralFocus }
        return clampFocus(neutralFocus + (g - 70.0) / staffSpan)
    }

    /// The per-play edge this club's OWN offense carries.
    /// Returns `(0, 0)` at neutral focus, exactly.
    static func offenseEdge(focus: Double) -> (completion: Double, run: Double) {
        let delta = clampFocus(focus) - neutralFocus
        return (delta * audibleCompletionSpan * 2.0, delta * audibleRunSpan * 2.0)
    }

    /// The per-play penalty this club's defensive preparation imposes on the
    /// OPPOSING offense. Sign is already negative for a well-prepared defense —
    /// the caller adds it to the opponent's offense adjustments.
    static func defenseEdge(focus: Double) -> (completion: Double, run: Double) {
        let delta = clampFocus(focus) - neutralFocus
        return (-delta * readCompletionSpan * 2.0, -delta * readRunSpan * 2.0)
    }

    static func clampFocus(_ value: Double) -> Double {
        Swift.min(1.0, Swift.max(0.0, value))
    }
}
