import Foundation

// MARK: - Coaching Modifiers (R40)

/// Turns a coaching staff's attributes into the small, bounded efficiency
/// nudges the play-by-play sim applies. Shared by `GameSimulator` (quick sim)
/// and `LiveGameEngine` (live 3D) so the two paths stay statistically
/// identical — a coordinator hire that helps the quick sim helps the live game
/// by exactly the same amount.
///
/// Every connection is a CONFIGURABLE coefficient centered so that:
///   * a team with **no** coach of the relevant role produces **zero** effect
///     (the pre-R40 behavior is byte-identical), and
///   * two league-average staffs (grade 70) roughly cancel, so the league-wide
///     scoring / completion / penalty aggregates hold while better-coached
///     teams separate.
///
/// Each mechanic carries its own DEBUG neutralization flag so the balance
/// harness (`GameSimulator.debugSimulate`) can measure it in isolation.
enum CoachingModifiers {

    // MARK: - Debug neutralization (balance harness only)

    #if DEBUG
    /// Mech 1 — OC/DC grade → completion + rushing efficiency.
    static var debugNeutralCoordinator = false
    /// Mech 2 — game-planning → small team efficiency edge.
    static var debugNeutralGamePlanning = false
    /// Mech 6 — coordinator scheme-expertise → direct completion/yard bonus.
    static var debugNeutralSchemeExpertise = false
    /// Mech 4 — discipline → penalty & fumble frequency.
    static var debugNeutralDiscipline = false
    /// Mech 3 — morale-influence → pre-game team morale.
    static var debugNeutralMoraleInfluence = false
    /// Mech 5 — head-coach motivation → pre-game team morale / game-day lift.
    static var debugNeutralMotivation = false
    #endif

    // MARK: - Tuning constants (all configurable)

    /// League-average coordinator grade — the neutral pivot.
    static let coordinatorCenter = 70.0
    /// Completion-probability shift per grade point above/below center.
    static let coordCompletionSlope = 0.0015
    /// Per-coordinator completion cap (±grade 30 saturates here).
    static let coordCompletionCap = 0.045
    /// Rushing yards/carry shift per grade point.
    static let coordRunSlope = 0.012
    static let coordRunCap = 0.35

    /// Game-planning is a smaller, secondary edge on top of the coordinator.
    static let planCenter = 70.0
    static let planCompletionSlope = 0.0006
    static let planCompletionCap = 0.018
    static let planRunSlope = 0.006
    static let planRunCap = 0.18

    /// Scheme expertise (in the scheme actually being run) is a positive-only
    /// specialist bonus above the center — a coordinator running the system he
    /// has mastered squeezes a little more out of it.
    static let schemeCenter = 70.0
    static let schemeCompletionSlope = 0.001
    static let schemeCompletionCap = 0.022
    static let schemeRunSlope = 0.009
    static let schemeRunCap = 0.22

    /// Net completion / run clamps after all three mechanics compose.
    static let netCompletionCap = 0.07
    static let netRunCap = 0.75

    /// Discipline scales the penalty-flag and fumble frequencies for a team's
    /// own snaps (offense-perspective). Centered so grade 70 = ×1.0.
    static let disciplineCenter = 70.0
    static let disciplineSlope = 0.010
    static let disciplineScaleMin = 0.72
    static let disciplineScaleMax = 1.28

    /// Pre-game morale bump (points of morale, clamped) applied to every
    /// snapshot player before kickoff.
    static let moraleCenter = 70.0
    static let moraleInfluenceSlope = 0.30
    static let motivationSlope = 0.20
    static let moraleBumpCap = 10.0

    // MARK: - Per-team rating snapshot

    /// The handful of coach attributes the sim consumes, extracted from a
    /// team's staff once per game. Any missing role leaves its field `nil`,
    /// which the math treats as "no effect".
    struct TeamRatings {
        var ocGrade: Double?
        var dcGrade: Double?
        var gamePlanning: Double?
        var discipline: Double?
        var moraleInfluence: Double?
        var motivation: Double?
        /// OC's expertise in the offensive scheme actually being run.
        var ocSchemeExpertise: Double?
        /// DC's expertise in the defensive scheme actually being run.
        var dcSchemeExpertise: Double?

        /// True when nothing in this staff can move the sim — lets callers
        /// preserve the exact pre-R40 (no-coach) path.
        var isNeutral: Bool {
            ocGrade == nil && dcGrade == nil && gamePlanning == nil
                && discipline == nil && moraleInfluence == nil && motivation == nil
        }
    }

    /// Extracts the sim-relevant ratings from a coaching staff. `nil` fields
    /// (missing roles) contribute nothing, so a staff with no coordinators is
    /// indistinguishable from today's coach-blind sim.
    static func ratings(from coaches: [Coach]) -> TeamRatings {
        var r = TeamRatings()
        let hc = coaches.first { $0.role == .headCoach }
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }

        if let oc {
            r.ocGrade = Double(oc.playCalling + oc.adaptability) / 2.0
            if let scheme = oc.offensiveScheme {
                r.ocSchemeExpertise = Double(oc.expertise(for: scheme.rawValue))
            }
        }
        if let dc {
            r.dcGrade = Double(dc.playCalling + dc.adaptability) / 2.0
            if let scheme = dc.defensiveScheme {
                r.dcSchemeExpertise = Double(dc.expertise(for: scheme.rawValue))
            }
        }

        // Game planning: the sharpest planner on staff sets the week's edge.
        let planners = coaches.filter {
            $0.role == .headCoach || $0.role == .assistantHeadCoach
                || $0.role == .offensiveCoordinator || $0.role == .defensiveCoordinator
        }
        if let bestPlan = planners.map({ $0.gamePlanning }).max() {
            r.gamePlanning = Double(bestPlan)
        }

        // Discipline: the head coach sets the culture; fall back to the best
        // coordinator when the HC seat is empty.
        if let hc {
            r.discipline = Double(hc.discipline)
        } else if let best = [oc, dc].compactMap({ $0 }).map({ $0.discipline }).max() {
            r.discipline = Double(best)
        }

        // Morale influence: any staffer can lift the room; take the best.
        if let bestMorale = coaches.map({ $0.moraleInfluence }).max() {
            r.moraleInfluence = Double(bestMorale)
        }
        // Motivation is the head coach's lever (game-day performance).
        if let hc { r.motivation = Double(hc.motivation) }

        return r
    }

    // MARK: - Offense adjustments (completion / run / penalty / fumble)

    /// Builds the offense-perspective `PlaySimulator.Adjustments` for one team
    /// on offense against a given defense. Positive completion/run favors the
    /// offense; the defending DC's grade and scheme expertise pull them back.
    /// Discipline scales the offense's own penalty and fumble frequencies.
    ///
    /// Returns `nil` when neither staff can affect the play, so the caller
    /// threads exactly the pre-R40 (no adjustments) path.
    static func offenseAdjustments(offense: TeamRatings, defense: TeamRatings) -> PlaySimulator.Adjustments? {
        if offense.isNeutral && defense.isNeutral { return nil }

        var completion = 0.0
        var run = 0.0

        // Mech 1 — coordinator grade.
        if coordinatorActive {
            if let oc = offense.ocGrade {
                completion += clampSym((oc - coordinatorCenter) * coordCompletionSlope, coordCompletionCap)
                run += clampSym((oc - coordinatorCenter) * coordRunSlope, coordRunCap)
            }
            if let dc = defense.dcGrade {
                completion -= clampSym((dc - coordinatorCenter) * coordCompletionSlope, coordCompletionCap)
                run -= clampSym((dc - coordinatorCenter) * coordRunSlope, coordRunCap)
            }
        }

        // Mech 2 — game planning (offense planner vs defense planner).
        if gamePlanningActive {
            if let off = offense.gamePlanning {
                completion += clampSym((off - planCenter) * planCompletionSlope, planCompletionCap)
                run += clampSym((off - planCenter) * planRunSlope, planRunCap)
            }
            if let def = defense.gamePlanning {
                completion -= clampSym((def - planCenter) * planCompletionSlope, planCompletionCap)
                run -= clampSym((def - planCenter) * planRunSlope, planRunCap)
            }
        }

        // Mech 6 — coordinator scheme expertise (positive-only specialist bonus).
        if schemeExpertiseActive {
            if let e = offense.ocSchemeExpertise {
                let t = max(0.0, e - schemeCenter)
                completion += min(t * schemeCompletionSlope, schemeCompletionCap)
                run += min(t * schemeRunSlope, schemeRunCap)
            }
            if let e = defense.dcSchemeExpertise {
                let t = max(0.0, e - schemeCenter)
                completion -= min(t * schemeCompletionSlope, schemeCompletionCap)
                run -= min(t * schemeRunSlope, schemeRunCap)
            }
        }

        let penaltyScale = disciplineScale(offense.discipline)

        var adj = PlaySimulator.Adjustments()
        adj.completionBonus = clampSym(completion, netCompletionCap)
        adj.runYardageBonus = clampSym(run, netRunCap)
        adj.penaltyChanceScale = penaltyScale
        adj.fumbleChanceScale = penaltyScale
        return adj
    }

    /// Pre-game morale delta from morale-influence (any staffer) + head-coach
    /// motivation. Raises the floor so fewer mood-dependent players dip under
    /// the low-morale penalty line; a poor staff drags it the other way.
    static func moraleBump(_ r: TeamRatings) -> Int {
        var bump = 0.0
        if moraleInfluenceActive, let mi = r.moraleInfluence {
            bump += (mi - moraleCenter) * moraleInfluenceSlope
        }
        if motivationActive, let mo = r.motivation {
            bump += (mo - moraleCenter) * motivationSlope
        }
        return Int(clampSym(bump, moraleBumpCap).rounded())
    }

    /// Field-wise combination of two adjustment bundles (coach edge + live
    /// halftime tweak). Additive for the +/- bonuses, multiplicative for the
    /// frequency scales. `nil` when both inputs are `nil`.
    static func combine(_ a: PlaySimulator.Adjustments?,
                        _ b: PlaySimulator.Adjustments?) -> PlaySimulator.Adjustments? {
        guard a != nil || b != nil else { return nil }
        let x = a ?? PlaySimulator.Adjustments()
        let y = b ?? PlaySimulator.Adjustments()
        var out = PlaySimulator.Adjustments()
        out.sackChanceReduction = x.sackChanceReduction + y.sackChanceReduction
        out.completionBonus = x.completionBonus + y.completionBonus
        out.runYardageBonus = x.runYardageBonus + y.runYardageBonus
        out.penaltyChanceScale = x.penaltyChanceScale * y.penaltyChanceScale
        out.fumbleChanceScale = x.fumbleChanceScale * y.fumbleChanceScale
        return out
    }

    // MARK: - Helpers

    private static func disciplineScale(_ grade: Double?) -> Double {
        guard disciplineActive, let g = grade else { return 1.0 }
        let scale = 1.0 - (g - disciplineCenter) * disciplineSlope
        return Swift.min(disciplineScaleMax, Swift.max(disciplineScaleMin, scale))
    }

    private static func clampSym(_ value: Double, _ cap: Double) -> Double {
        Swift.min(cap, Swift.max(-cap, value))
    }

    // Each flag defaults to active; the DEBUG harness can neutralize one at a
    // time. Release builds hard-wire "active" so there is zero runtime cost.
    private static var coordinatorActive: Bool {
        #if DEBUG
        return !debugNeutralCoordinator
        #else
        return true
        #endif
    }
    private static var gamePlanningActive: Bool {
        #if DEBUG
        return !debugNeutralGamePlanning
        #else
        return true
        #endif
    }
    private static var schemeExpertiseActive: Bool {
        #if DEBUG
        return !debugNeutralSchemeExpertise
        #else
        return true
        #endif
    }
    private static var disciplineActive: Bool {
        #if DEBUG
        return !debugNeutralDiscipline
        #else
        return true
        #endif
    }
    private static var moraleInfluenceActive: Bool {
        #if DEBUG
        return !debugNeutralMoraleInfluence
        #else
        return true
        #endif
    }
    private static var motivationActive: Bool {
        #if DEBUG
        return !debugNeutralMotivation
        #else
        return true
        #endif
    }
}
