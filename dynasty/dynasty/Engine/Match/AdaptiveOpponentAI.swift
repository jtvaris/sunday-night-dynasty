import Foundation

// MARK: - Adaptive Opponent AI (live games only)

/// Tendency tracking and counter-call selection for the AI side of a LIVE
/// coached game: "if the coach keeps calling the same play, the opponent
/// adapts" — in both directions.
///
/// The ``Tracker`` records the PLAYER's explicit calls in this game,
/// recency-weighted (last ~10 calls, weight `0.85^age`):
///   • on offense per category (inside run / outside run / screen / short /
///     medium / deep / play action, derived from the call) plus the exact
///     play, and
///   • on defense per family (man/zone share, blitz share, single-high
///     share, derived from the ``DefensivePackage``).
///
/// Once a pattern crosses its trigger threshold, `LiveGameEngine` mixes
/// counter calls into the AI's base logic:
///   • player attacks → ``defensiveCounter(for:scheme:)`` packages replace
///     the base ``LiveGameEngine/aiDefensivePackage()`` pick on a share of
///     snaps (never the red-zone sellout or the late-lead prevent shell);
///   • player defends → ``offensiveCounter(for:scheme:distance:yardsToEndzone:)``
///     plays are checked into via ``LiveGameEngine/aiOffensiveCall()``
///     (nil = today's base `PlaySimulator.decidePlayCall`).
///
/// Both the trigger threshold and the counter share scale with the OPPONENT
/// coordinator's grade (`(playCalling + adaptability) / 2`): a weak DC keys
/// only on a ~50% tendency and counters rarely; an elite one keys at ~30–35%
/// and counters hard. The counter share is capped at ``maxCounterShare`` so
/// the AI never turns deterministic, and counters act purely through the
/// existing play-vs-play modifiers (package modifiers / simulator hints) —
/// there is no hidden "predictability" malus. Mixing your calls drops the
/// tendency back below the threshold and the AI returns to base logic.
///
/// Quick-sim parity: nothing here is reachable from a nil-argument
/// `LiveGameEngine.step` — the tracker fills only from the player's explicit
/// live calls — and `GameSimulator.simulate` never touches this type.
enum AdaptiveOpponentAI {

    // MARK: - Tuning

    /// How many of the player's most recent calls the tracker keeps.
    static let historyWindow = 10
    /// Per-age weight decay (newest call = 1.0, previous = 0.85, ...).
    static let recencyDecay = 0.85
    /// Minimum recorded calls before a weighted share can trigger.
    static let minSampleSize = 5
    /// The same exact play in 3 of the last 5 calls also triggers a counter.
    static let exactPlayWindow = 5
    static let exactPlayTrigger = 3
    /// Counter calls never exceed this share of AI snaps.
    static let maxCounterShare = 0.60

    /// Nominal (grade-50 coordinator) tendency thresholds per family.
    static let offenseCategoryBaseThreshold = 0.40
    static let blitzBaseThreshold = 0.45
    static let manBaseThreshold = 0.50
    /// Zone is the default fabric of most call sheets, so the AI only calls
    /// a player "zone-heavy" when he is nearly zone-pure.
    static let zoneBaseThreshold = 0.65
    static let singleHighBaseThreshold = 0.50

    /// Trigger threshold for a coordinator grade: grade 50 = the base value,
    /// an elite (100) coordinator keys 10 points sooner, a poor (0) one 10
    /// points later — "weak DC: ~50%+, elite: ~30–35%".
    static func scaledThreshold(base: Double, coordinatorGrade: Int) -> Double {
        base + 0.10 - 0.20 * grade01(coordinatorGrade)
    }

    /// How often the AI actually calls the counter once a tendency triggered:
    /// 0.20 for a poor coordinator up to ``maxCounterShare`` for an elite one.
    static func counterShare(coordinatorGrade: Int) -> Double {
        min(maxCounterShare, max(0.15, 0.20 + 0.40 * grade01(coordinatorGrade)))
    }

    private static func grade01(_ grade: Int) -> Double {
        min(1.0, max(0.0, Double(grade) / 100.0))
    }

    // MARK: - Offensive tendencies (player attacks)

    /// The coarse category a player's offensive call is tracked under.
    enum OffenseTendency: String, CaseIterable {
        case insideRun, outsideRun, screen, shortPass, mediumPass, deepPass, playAction
    }

    /// Derives the tracked category from the call's own metadata (category +
    /// run-gap / pass-depth hints). Spike/kneel are clock plays, not
    /// tendencies — they return nil and are never recorded.
    static func tendency(of call: OffensivePlayCall) -> OffenseTendency? {
        switch call {
        case .insideRun, .counter, .draw, .dive, .qbSneak: return .insideRun
        case .outsideRun, .toss, .jetSweep:                return .outsideRun
        case .screen:                                      return .screen
        case .slant, .quickOut, .hitch, .flat, .drag, .stick, .mesh:
            return .shortPass
        case .curl, .dig, .seam, .cross, .postCorner, .comeback, .wheel:
            return .mediumPass
        case .goRoute, .post, .corner, .flood, .bomb:      return .deepPass
        case .playActionDeep:                              return .playAction
        case .spike, .kneel:                               return nil
        }
    }

    // MARK: - Defensive tendencies (player defends)

    /// The defensive family the AI offense exploits.
    enum DefenseTendency: String, CaseIterable {
        case blitzHeavy, manHeavy, zoneHeavy, singleHighHeavy
    }

    /// One recorded defensive snap, classified from the player's package.
    struct DefenseSnap {
        let isMan: Bool
        let isBlitz: Bool
        let isZone: Bool
        let isSingleHigh: Bool

        init(package: DefensivePackage) {
            isMan = package.coverage == .manToMan
            isBlitz = package.blitz != .noBlitz
            isZone = !isMan
            isSingleHigh = package.coverage == .cover1 || package.coverage == .cover3
        }
    }

    // MARK: - Tracker

    /// The player's call history for the current game (newest last).
    struct Tracker {
        private(set) var offenseCalls: [OffensivePlayCall] = []
        private(set) var defenseSnaps: [DefenseSnap] = []

        mutating func recordOffense(_ call: OffensivePlayCall) {
            guard AdaptiveOpponentAI.tendency(of: call) != nil else { return }
            offenseCalls.append(call)
            if offenseCalls.count > AdaptiveOpponentAI.historyWindow {
                offenseCalls.removeFirst(offenseCalls.count - AdaptiveOpponentAI.historyWindow)
            }
        }

        mutating func recordDefense(_ package: DefensivePackage) {
            defenseSnaps.append(DefenseSnap(package: package))
            if defenseSnaps.count > AdaptiveOpponentAI.historyWindow {
                defenseSnaps.removeFirst(defenseSnaps.count - AdaptiveOpponentAI.historyWindow)
            }
        }

        /// The offensive tendency currently over the trigger line, if any:
        /// either the same exact play in 3 of the last 5 calls, or a category
        /// holding at least `threshold` of the recency-weighted call mass.
        func dominantOffenseTendency(threshold: Double) -> OffenseTendency? {
            // Exact-play spam reads instantly (no minimum sample needed).
            if offenseCalls.count >= AdaptiveOpponentAI.exactPlayTrigger {
                let recent = offenseCalls.suffix(AdaptiveOpponentAI.exactPlayWindow)
                let counts = Dictionary(grouping: recent, by: { $0 }).mapValues(\.count)
                if let (call, count) = counts.max(by: { $0.value < $1.value }),
                   count >= AdaptiveOpponentAI.exactPlayTrigger,
                   let tendency = AdaptiveOpponentAI.tendency(of: call) {
                    return tendency
                }
            }
            guard offenseCalls.count >= AdaptiveOpponentAI.minSampleSize else { return nil }
            var mass: [OffenseTendency: Double] = [:]
            var total = 0.0
            for (age, call) in offenseCalls.reversed().enumerated() {
                let weight = pow(AdaptiveOpponentAI.recencyDecay, Double(age))
                total += weight
                if let tendency = AdaptiveOpponentAI.tendency(of: call) {
                    mass[tendency, default: 0] += weight
                }
            }
            guard total > 0, let best = mass.max(by: { $0.value < $1.value }) else { return nil }
            return best.value / total >= threshold ? best.key : nil
        }

        /// The defensive family currently over its trigger line, if any —
        /// the strongest signal (largest margin over its own scaled
        /// threshold) wins when several families qualify at once.
        func dominantDefenseTendency(coordinatorGrade: Int) -> DefenseTendency? {
            guard defenseSnaps.count >= AdaptiveOpponentAI.minSampleSize else { return nil }
            var blitz = 0.0, man = 0.0, zone = 0.0, singleHigh = 0.0, total = 0.0
            for (age, snap) in defenseSnaps.reversed().enumerated() {
                let weight = pow(AdaptiveOpponentAI.recencyDecay, Double(age))
                total += weight
                if snap.isBlitz { blitz += weight }
                if snap.isMan { man += weight }
                if snap.isZone { zone += weight }
                if snap.isSingleHigh { singleHigh += weight }
            }
            guard total > 0 else { return nil }
            func threshold(_ base: Double) -> Double {
                AdaptiveOpponentAI.scaledThreshold(base: base, coordinatorGrade: coordinatorGrade)
            }
            let margins: [(tendency: DefenseTendency, margin: Double)] = [
                (.blitzHeavy, blitz / total - threshold(AdaptiveOpponentAI.blitzBaseThreshold)),
                (.manHeavy, man / total - threshold(AdaptiveOpponentAI.manBaseThreshold)),
                (.zoneHeavy, zone / total - threshold(AdaptiveOpponentAI.zoneBaseThreshold)),
                (.singleHighHeavy, singleHigh / total - threshold(AdaptiveOpponentAI.singleHighBaseThreshold))
            ]
            guard let best = margins.max(by: { $0.margin < $1.margin }), best.margin >= 0 else {
                return nil
            }
            return best.tendency
        }
    }

    // MARK: - Counter pools

    /// Defensive counter calls per offensive tendency (existing call-sheet
    /// calls — their package modifiers ARE the counter, no extra malus).
    static func defensiveCounterCalls(for tendency: OffenseTendency) -> [DefensiveCall] {
        switch tendency {
        case .insideRun:          return [.bearFront, .goalLineD, .doubleAGap]
        case .outsideRun:         return [.cornerBlitz, .safetyBlitz, .cover2Shell]
        case .screen, .shortPass: return [.manPress, .twoManUnder, .nickelPackage]
        case .mediumPass:         return [.twoManUnder, .cover4Match, .dimePackage]
        case .deepPass:           return [.cover2Shell, .quarters, .twoManUnder]
        case .playAction:         return [.cover3Base, .quarters, .cover4Match]
        }
    }

    /// A counter package for the AI defense, preferring calls installed in
    /// its coordinator's playbook.
    static func defensiveCounter(
        for tendency: OffenseTendency,
        scheme: DefensiveScheme?
    ) -> DefensivePackage {
        let pool = defensiveCounterCalls(for: tendency)
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        return ((installed.isEmpty ? pool : installed).randomElement() ?? .cover3Base).package
    }

    /// Offensive counter plays per defensive tendency: blitz-heavy defenses
    /// eat screens/quick game/draws, man gets crossers, zone gets seams and
    /// curl holes, single-high shells get attacked over the top.
    static func offensiveCounterCalls(for tendency: DefenseTendency) -> [OffensivePlayCall] {
        switch tendency {
        case .blitzHeavy:      return [.screen, .slant, .quickOut, .draw, .flat]
        case .manHeavy:        return [.mesh, .drag, .cross]
        case .zoneHeavy:       return [.seam, .curl, .dig, .stick]
        case .singleHighHeavy: return [.post, .playActionDeep, .goRoute, .corner]
        }
    }

    /// A counter play for the AI offense, filtered for basic situational
    /// sanity (no draws on long yardage, no deep shots near the goal line)
    /// and preferring the coordinator's installed playbook. `nil` = no sane
    /// counter here — the AI stays on base logic for this snap.
    static func offensiveCounter(
        for tendency: DefenseTendency,
        scheme: OffensiveScheme?,
        distance: Int,
        yardsToEndzone: Int
    ) -> OffensivePlayCall? {
        var pool = offensiveCounterCalls(for: tendency)
        if distance >= 8 { pool.removeAll { $0.isRun && $0 != .screen } }
        if yardsToEndzone < 25 {
            pool.removeAll { $0.simulatorHint.passDepth == .deep || $0 == .playActionDeep }
        }
        guard !pool.isEmpty else { return nil }
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        return (installed.isEmpty ? pool : installed).randomElement()
    }

    // MARK: - Broadcast hints

    /// Feed line when the AI DEFENSE starts keying on the player's offense.
    static func defenseKeyHint(for tendency: OffenseTendency, opponentAbbr: String) -> String {
        switch tendency {
        case .insideRun:  return "\(opponentAbbr) is keying on the inside run"
        case .outsideRun: return "\(opponentAbbr) is stringing out your sweeps — they've seen the edge run"
        case .screen:     return "\(opponentAbbr) is sniffing out the screen game"
        case .shortPass:  return "They're sitting on your short routes"
        case .mediumPass: return "They're squeezing the intermediate windows"
        case .deepPass:   return "\(opponentAbbr) is dropping two deep — the shot plays are covered"
        case .playAction: return "They've stopped biting on the play fake"
        }
    }

    /// Feed line when the AI OFFENSE starts exploiting the player's defense.
    static func offenseAdjustHint(for tendency: DefenseTendency, qbName: String) -> String {
        switch tendency {
        case .blitzHeavy:      return "\(qbName) checks to the quick game — they saw the blitz coming"
        case .manHeavy:        return "They're attacking your man coverage with crossers"
        case .zoneHeavy:       return "They're working the soft spots in your zone"
        case .singleHighHeavy: return "They're taking shots at your single-high safety"
        }
    }
}
