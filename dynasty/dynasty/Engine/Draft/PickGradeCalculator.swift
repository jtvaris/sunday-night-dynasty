import Foundation

/// Computes the public-facing draft pick grade from visible signals.
/// See `docs/plans/2026-05-05-draft-day-design.md` §5.
enum PickGradeCalculator {

    /// Inputs visible to fans/media at the moment a pick is made.
    ///
    /// ## The user's own board is NOT one of them, and must not become one
    ///
    /// An audit filed this as a defect — a reveal card reading `A+` in one
    /// corner and `MY #101 · -50 REACH` in the other — and proposed feeding
    /// `DraftDayCoordinator.userBoardRanks` in here. That is the wrong half of
    /// the card to change, for three reasons that are checkable in this tree:
    ///
    ///   * **This grade is not blind to the user's scouting already.**
    ///     `publicOVR` is `DraftIntel.publicOVREstimate`, which returns
    ///     `scoutedOverall` when his building has filed on the man and the
    ///     media band only when nobody has. What it does not read is
    ///     `UserDraftBoard` — the drag-ordered list — which is a *preference*,
    ///     not information the media could have.
    ///   * **It grades all 32 clubs' cards.** `computePickGrade` runs on every
    ///     pick in the room, so a user-board term would make Cleveland's grade
    ///     for Cleveland's pick move when the user re-orders his own board.
    ///   * **It would rebuild the systematic REACH that task #155 tore out.**
    ///     `UserDraftBoard.order(among:)` appends every man the board has never
    ///     seen *behind* the stored order, so on a night where the user has
    ///     scouted sixty prospects everybody else starts at slot 61+. Grading
    ///     against that stamps REACH on most of the class for no reason but
    ///     unfinished scouting — the same shape of fault as the old
    ///     `needScore <= 0.3` row documented under ``letterGrade(from:)``,
    ///     arriving through a different door.
    ///
    /// The two numbers on that card are two frames, not one broken one. The
    /// repair is the key: `DraftTickerPanel.PickRevealCard.gradeChip` prints
    /// `MEDIA A+ STEAL` and `boardRow` prints `MY #101 · -50 REACH`, so the
    /// card names whose opinion each is.
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
        let base = letterGrade(from: inputs)
        let grade = applySchemeNudge(base: base, inputs: inputs)
        let isGem = inputs.valueDelta >= 6 && inputs.needScore >= 0.7
        return Output(grade: grade, compositeScore: composite, isGemCandidate: isGem)
    }

    // MARK: - Private

    /// Applies a bounded, one-step adjustment for scheme fit (#33 OSA B). The
    /// core letter grade follows Design §5 (value / need / OVR); scheme fit only
    /// nudges the middle B/A/C band by a single step, so a prospect landing in
    /// an ideal system grades out better than the same player into a poor fit —
    /// without overriding the strong Steal (A+) or Big-Reach (D) signals. Before
    /// #33 `schemeFit` was a flat 0.6 constant that never moved a grade; a real
    /// per-team fit now feeds this rule.
    private static func applySchemeNudge(base: PickGrade, inputs: Inputs) -> PickGrade {
        let fit = clamp01(inputs.schemeFit)
        // Strong fit: promote a Solid (B) to Smart (A) when the pick is sound.
        if fit >= 0.75, base == .solid, inputs.publicOVR >= 72, inputs.valueDelta >= -3 {
            return .smartA
        }
        // Poor fit: demote by one step within the middle band.
        if fit <= 0.45 {
            if base == .smartA { return .solid }
            if base == .solid, inputs.needScore < 0.5 { return .reach }
        }
        return base
    }

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
    ///
    /// ## A reach is a BOARD fact, not a need fact (task #155)
    ///
    /// The `C Reach` row used to read `valueDelta <= -6 || needScore <= 0.3`.
    /// The second half of that `||` graded a pick on need ALONE, and
    /// `DraftDayCoordinator.computePickGrade` feeds it
    /// `DraftIntel.teamNeedScores(roster:)[position] ?? 0.2` — a table with only
    /// six rows, whose sixth entry is exactly `0.3`. So every pick at a position
    /// outside the club's top FIVE needs arrived with `needScore <= 0.3` and was
    /// stamped REACH before the public board was consulted at all: a man taken
    /// dead on his mock slot, a man who slid two rounds, a man nobody in the
    /// building disagreed about.
    ///
    /// It is worse than a sixth-place cutoff sounds, because `teamNeedScores`
    /// ranks on `topTeamNeeds`, which on a full 53-man roster collapses to the
    /// positional-value quintet {QB, DE, CB, WR, LT} for *every club in the
    /// league* (see `DraftEngine.teamNeedComponents`). Fourteen of the nineteen
    /// positions could therefore never be graded better than REACH by anybody,
    /// in any year — which is precisely the systematic REACH the AI draft cards
    /// were reported to show.
    ///
    /// A reach means one thing: **the club took him ahead of where the market
    /// had him.** That is `valueDelta`, and only `valueDelta` can open the door.
    /// Need still speaks — it decides how far ahead of the board counts as too
    /// far, and it is 25 % of `compositeScore` — but it no longer convicts on
    /// its own.
    private static func letterGrade(from inputs: Inputs) -> PickGrade {
        // A+ Steal — he lasted past the media's window and fills a hole.
        if inputs.valueDelta >= 6 && inputs.needScore >= 0.6 {
            return .stealAPlus
        }
        // A+ Steal — or the board simply fell to him. At a full round past the
        // window the value is the story whatever the roster looked like; this is
        // the "best value of the round" card, which the need-gated row above
        // could never award to a club that was already set at the position.
        if inputs.valueDelta >= 12 {
            return .stealAPlus
        }
        // D Big Reach (check before C so it wins when both fire)
        if inputs.valueDelta <= -10 && inputs.needScore <= 0.3 {
            return .bigReach
        }
        // C Reach — a long jump ahead of the market on its own, or a short one
        // the roster gives no reason for.
        if inputs.valueDelta <= -6 || (inputs.valueDelta <= -2 && inputs.needScore <= 0.3) {
            return .reach
        }
        // A Smart Pick
        if inputs.valueDelta >= 0 && inputs.needScore >= 0.5 && inputs.publicOVR >= 75 {
            return .smartA
        }
        // A Smart Pick — good value on a good player, even where the club was
        // not shopping. Taking the better man is not a mistake.
        if inputs.valueDelta >= 4 && inputs.publicOVR >= 75 {
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
