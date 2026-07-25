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

    /// Alias for ``tendency(of:)`` — reads clearer where the "concept" framing
    /// of the PLAY-MEMORY layers (category / exact / counter) is what matters.
    static func concept(of call: OffensivePlayCall) -> OffenseTendency? {
        tendency(of: call)
    }

    /// The mirror map (Layer B counter-play): when the AI defense is
    /// ANTICIPATING `tendency`, these are the offensive CONCEPTS that open up
    /// against it. Each design play-name is collapsed to its `OffenseTendency`
    /// (toss→outsideRun, counter/draw→insideRun, quickGame→shortPass) and the
    /// anticipated concept itself is never listed (you can't open the very read
    /// the defense is sitting on). The deep-shot entry a run key would open
    /// (insideRun→playAction) is suppressed by the caller whenever the existing
    /// `paKey` levers already own the deep punish — see `counterOpen`.
    static func counterConcepts(for tendency: OffenseTendency) -> [OffenseTendency] {
        switch tendency {
        case .insideRun:  return [.outsideRun, .playAction]        // + short game via the category channel
        case .outsideRun: return [.insideRun]                      // counter / draw both read as insideRun
        case .shortPass:  return [.insideRun, .mediumPass]         // draw, then work the intermediate
        case .mediumPass: return [.screen, .insideRun, .deepPass]  // screen / draw underneath, shot over the top
        case .deepPass:   return [.shortPass, .screen, .insideRun] // take the free underneath / draw
        case .screen:     return [.insideRun, .mediumPass]
        case .playAction: return [.shortPass]                      // quick game beats a squatted PA read
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

        /// True until the player's first explicit live call is recorded —
        /// the engine gates ALL persona/counter RNG on this so nil-argument
        /// games stay RNG-identical to today (quick-sim parity).
        var isEmpty: Bool { offenseCalls.isEmpty && defenseSnaps.isEmpty }

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
        /// `thresholdOffset` is the OC persona's shade (R33): negative =
        /// keys sooner, positive = more stubborn. 0 = today's behavior.
        func dominantDefenseTendency(
            coordinatorGrade: Int,
            thresholdOffset: Double = 0
        ) -> DefenseTendency? {
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
                    + thresholdOffset
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
    /// The DC persona (R33) colors the line — an aggressive DC "sells out",
    /// an exotic one gets weirder; balanced/conservative read as today.
    static func defenseKeyHint(
        for tendency: OffenseTendency,
        opponentAbbr: String,
        persona: DCPersona = .balanced
    ) -> String {
        // The spec line: an aggressive DC vs a run tendency.
        if persona == .aggressive, tendency == .insideRun || tendency == .outsideRun {
            return "Their aggressive DC is all-in on stopping the run"
        }
        let base: String
        switch tendency {
        case .insideRun:  base = "\(opponentAbbr) is keying on the inside run"
        case .outsideRun: base = "\(opponentAbbr) is stringing out your sweeps — they've seen the edge run"
        case .screen:     base = "\(opponentAbbr) is sniffing out the screen game"
        case .shortPass:  base = "They're sitting on your short routes"
        case .mediumPass: base = "They're squeezing the intermediate windows"
        case .deepPass:   base = "\(opponentAbbr) is dropping two deep — the shot plays are covered"
        case .playAction: base = "They've stopped biting on the play fake"
        }
        switch persona {
        case .aggressive: return base + " — their aggressive DC is selling out to take it away"
        case .exotic:     return base + " — and the pressure looks keep getting stranger"
        case .conservative, .balanced: return base
        }
    }

    /// Feed line when the AI DEFENSE has locked onto the EXACT play the coach
    /// keeps calling (Layer B exact-call layer — fires on the 3rd identical
    /// call). Uses the call's own sheet name ("BAL is sitting on the toss
    /// sweep").
    static func exactCallHint(
        for call: OffensivePlayCall,
        opponentAbbr: String,
        persona: DCPersona = .balanced
    ) -> String {
        let name = call.rawValue.lowercased()
        switch persona {
        case .aggressive: return "\(opponentAbbr) has jumped the \(name) — they're sitting on it now"
        case .exotic:     return "\(opponentAbbr) is sitting on the \(name) out of a strange look"
        case .conservative, .balanced: return "\(opponentAbbr) is sitting on the \(name)"
        }
    }

    /// Feed line when the AI DEFENSE has keyed a broad CONCEPT (Layer B
    /// category layer — fires when the recency-weighted share crosses the read
    /// threshold, ~0.5 anticipation). Broader than ``exactCallHint``: the coach
    /// is leaning on a whole family, not one literal call.
    static func categoryKeyHint(
        for concept: OffenseTendency,
        opponentAbbr: String,
        persona: DCPersona = .balanced
    ) -> String {
        let base: String
        switch concept {
        case .insideRun:  base = "\(opponentAbbr) is loading up against the inside run"
        case .outsideRun: base = "\(opponentAbbr) is setting the edge — they've keyed your outside game"
        case .screen:     base = "\(opponentAbbr) is squatting on the screen game"
        case .shortPass:  base = "\(opponentAbbr) is squatting on the quick game"
        case .mediumPass: base = "\(opponentAbbr) is squeezing the intermediate windows"
        case .deepPass:   base = "\(opponentAbbr) is loading up for the deep ball"
        case .playAction: base = "\(opponentAbbr) has stopped biting on the play fake"
        }
        switch persona {
        case .aggressive: return base + " — their DC is selling out to take it away"
        case .exotic:     return base + " — and the front keeps getting stranger"
        case .conservative, .balanced: return base
        }
    }

    /// Feed line when the AI OFFENSE starts exploiting the player's defense,
    /// colored by the OC persona (R33).
    static func offenseAdjustHint(
        for tendency: DefenseTendency,
        qbName: String,
        persona: OCPersona = .balanced
    ) -> String {
        let base: String
        switch tendency {
        case .blitzHeavy:      base = "\(qbName) checks to the quick game — they saw the blitz coming"
        case .manHeavy:        base = "They're attacking your man coverage with crossers"
        case .zoneHeavy:       base = "They're working the soft spots in your zone"
        case .singleHighHeavy: base = "They're taking shots at your single-high safety"
        }
        switch persona {
        case .groundAndPound: return base + " — but they'd still rather run it at you"
        case .airRaid:        return base + " — the Air Raid smells blood"
        case .westCoast:      return base + " — rhythm throws, right on schedule"
        case .balanced:       return base
        }
    }

    // MARK: - Run-Key Adaptation (Layer A — shared by coached + simmed paths)

    /// A save-free, per-game EWMA of the CURRENT offense's run share, bucketed
    /// by down so a 3rd-and-long pass doesn't wipe out the early-down read.
    ///
    /// This is the one component both engines share: `LiveGameEngine` (coached)
    /// and `DriveSimulator`/`GameSimulator` (simmed) each own instances and feed
    /// them identically — record `isRun` after every scrimmage snap, read
    /// `keyIntensity(down:)` before the next one. Once the offense's run share
    /// climbs past ``keyPivot`` the defense "keys" the run with escalating
    /// intensity (0…1), which the resolution turns into a yard bite + stuff
    /// bonus (A2) while opening the play-action / deep counter (A3).
    ///
    /// Purely in-memory: **no `Codable` conformance, never persisted** — the
    /// state lives for exactly one game and is rebuilt from scratch each time.
    struct RunKeyState {
        // Two buckets so a 3rd-and-long pass doesn't wipe the early-down read.
        private(set) var earlyDownRunShare = 0.5   // downs 1–2
        private(set) var lateDownRunShare  = 0.5   // downs 3–4
        static let alpha    = 0.18   // ROUND-6: 0.30 → 0.18. A Bernoulli run/pass
        // stream makes the EWMA noisy (at α=0.30 its sd ≈ 0.20), so a balanced
        // offense's ~0.45 read randomly spiked past any run-heavy pivot ~25-30% of
        // snaps — false-positive keying that cooled the equal-tier run game. The
        // smoother 0.18 (sd ≈ 0.16) needs a SUSTAINED run tendency to cross the
        // pivot, so a truly predictable run-heavy offense still keys (and collapses
        // LATE as the read builds) while a balanced offense stays clear.
        // ROUND-6 re-dial (restore the run-heavy adaptation penalty). The prior
        // 0.65 pivot was set to "cleanly separate" the two styles, but it sat ABOVE
        // what the run-heavy knob actually produces: after P0-1 trimmed the early-down
        // pass weights, a run-heavy plan (runPassRatio 0.25) runs only ~58-62% on early
        // downs — its EWMA never crossed 0.65, so `keyIntensity` stayed ~0 and the
        // defense NEVER keyed it. That (plus P0-1 removing the pass-inflation
        // opportunity cost) is why the run-heavy win-penalty collapsed to ~0. Re-dialed
        // so a persistent run-heavy tendency (~0.60) IS keyed while a balanced offense
        // (~0.49 early-down run share, measured) stays clear: pivot 0.56 sits in the
        // ~0.10-wide gap between the two styles, and a steeper `keyFull` 0.80 (was 0.95)
        // makes a sustained run offense's rushing collapse late as its EWMA climbs —
        // full key by an all-run ~0.80 share. FIXED-BASELINE-inert: the keyed-PA anchor
        // passes a hardcoded intensity 1.0 and the run bands pass 0, so neither reads
        // these constants; only the live full-game / coached keying does.
        static let keyPivot = 0.55   // below → not keyed (balanced ~0.45 stays clear; run-heavy ~0.58 keys)
        static let keyFull  = 0.72   // at/above → full intensity (steeper ⇒ predictable run collapses late)

        /// Fold one resolved scrimmage snap into the down-bucketed EWMA.
        mutating func record(isRun: Bool, down: Int) {
            let x = isRun ? 1.0 : 0.0
            if down <= 2 {
                earlyDownRunShare = Self.alpha * x + (1 - Self.alpha) * earlyDownRunShare
            } else {
                lateDownRunShare = Self.alpha * x + (1 - Self.alpha) * lateDownRunShare
            }
        }

        /// 0…1 — how hard the defense is keying the run on THIS down. 0 below
        /// the pivot, ramping to 1 at/above `keyFull`.
        /// Ramp (start 0.5, α=0.30, pivot 0.65): run3→0.83 (0.60), run6→0.94
        /// (0.97), run8→0.97 (cap 1.0) — full key by run ~6.
        func keyIntensity(down: Int) -> Double {
            let s = down <= 2 ? earlyDownRunShare : lateDownRunShare
            let raw = (s - Self.keyPivot) / (Self.keyFull - Self.keyPivot)
            return Swift.min(1.0, Swift.max(0.0, raw))
        }

        /// True once the key is meaningfully engaged (intensity past ~0.15) —
        /// drives the front-selection bias (A4) and the early UI read (A6).
        func isKeyed(down: Int) -> Bool { keyIntensity(down: down) > 0.15 }
    }

    // MARK: - Play-Memory (Layer B — coached path; COMPOSES RunKeyState)

    /// A save-free, per-game read that OWNS (never replaces) ``RunKeyState`` and
    /// stacks two coached-only layers on the run/pass macro read:
    ///
    /// 1. CATEGORY — one down-bucketed EWMA per ``OffenseTendency`` concept, fed
    ///    1.0 on a snap of that concept and 0.0 otherwise. The 7 EWMAs sum to ~1,
    ///    so each is that concept's recency-weighted share; `anticipation` maps a
    ///    share above `catPivot` into 0…1. A mixed caller's neutral share (~1/7 ≈
    ///    0.14) sits far below the pivot, so every delta stays 0 (balanced-control
    ///    guarantee).
    /// 2. EXACT-CALL — a 4-wide ring of the literal last calls. `exactPunish`
    ///    bites the moment the SAME call repeats (2nd call already), ramping
    ///    faster and harder than the category EWMA, and drops to 0 the instant the
    ///    caller switches.
    ///
    /// Both feed pure probability/value SHIFTS at existing `PlaySimulator` sites
    /// (identity at 0 → parity-safe). Persona/grade move only the TIMING of the
    /// category read (`catPivot` = when, `catAlpha` = how fast), never the bite
    /// ceiling, so an elite DC keys sooner but never becomes an unfair wall.
    ///
    /// Purely in-memory: **no `Codable`, never persisted** — one game's life only.
    struct PlayMemory {
        /// The owned run/pass macro read (Layer A). All the shipped call sites
        /// forward to it through this facet, so the sim path is byte-identical.
        var runKey = RunKeyState()

        /// Down-bucketed category EWMAs (early ≤2 / late ≥3), uniform 1/7 prior
        /// so a fresh game reads anticipation 0 for every concept.
        var earlyCat: [OffenseTendency: Double] =
            Dictionary(uniqueKeysWithValues: OffenseTendency.allCases.map { ($0, 1.0 / 7.0) })
        var lateCat: [OffenseTendency: Double] =
            Dictionary(uniqueKeysWithValues: OffenseTendency.allCases.map { ($0, 1.0 / 7.0) })

        /// The literal last `exactWindow` recorded calls (newest last).
        var exactRing: [OffensivePlayCall] = []

        /// Category read TIMING, configured once by the engine from the AI DC's
        /// persona + grade (defaults = the grade-50 / balanced neutral). These
        /// move only WHEN / HOW FAST the read arms — never the bite ceiling.
        var catPivot: Double = AdaptiveOpponentAI.catPivot(thresholdOffset: 0, grade: 50)
        var catAlpha: Double = AdaptiveOpponentAI.catAlpha(thresholdOffset: 0, grade: 50)

        // MARK: Forwarders to the owned RunKeyState (macro read facet)

        func keyIntensity(down: Int) -> Double { runKey.keyIntensity(down: down) }
        func isKeyed(down: Int) -> Bool { runKey.isKeyed(down: down) }
        /// Sim-path forwarder (Tier 2): fold a resolved run/pass into the macro
        /// read only. The coached path uses ``record(call:down:)`` instead.
        mutating func record(isRun: Bool, down: Int) { runKey.record(isRun: isRun, down: down) }

        // MARK: Recording (coached path)

        /// Fold one resolved coached snap into all three layers. Spike/kneel
        /// (concept == nil) touch nothing — matching the shipped run-key gate.
        /// The macro facet counts a screen as a PASS (`playType(for:) == .pass`)
        /// so the run/pass read is byte-identical to the shipped `offenseRunKey`.
        mutating func record(call: OffensivePlayCall, down: Int) {
            guard let concept = AdaptiveOpponentAI.concept(of: call) else { return }
            let a = catAlpha
            if down <= 2 {
                for c in OffenseTendency.allCases {
                    let x = (c == concept) ? 1.0 : 0.0
                    earlyCat[c] = a * x + (1 - a) * (earlyCat[c] ?? 1.0 / 7.0)
                }
            } else {
                for c in OffenseTendency.allCases {
                    let x = (c == concept) ? 1.0 : 0.0
                    lateCat[c] = a * x + (1 - a) * (lateCat[c] ?? 1.0 / 7.0)
                }
            }
            exactRing.append(call)
            if exactRing.count > AdaptiveOpponentAI.exactWindow {
                exactRing.removeFirst(exactRing.count - AdaptiveOpponentAI.exactWindow)
            }
            // Screen is routed as a pass (see `PlaySimulator.playType(for:)`), so
            // it must NOT count as a run in the macro EWMA.
            runKey.record(isRun: call.isRun && call != .screen, down: down)
        }

        // MARK: Category anticipation

        /// 0…1 recency-weighted anticipation of `concept` on this down: 0 below
        /// `catPivot`, ramping to 1 at/above `catFull`. `nil` concept → 0.
        func anticipation(of concept: OffenseTendency?, down: Int) -> Double {
            guard let concept else { return 0 }
            let bucket = down <= 2 ? earlyCat : lateCat
            let total = bucket.values.reduce(0, +)
            guard total > 0 else { return 0 }
            let share = (bucket[concept] ?? 0) / total
            let raw = (share - catPivot) / (AdaptiveOpponentAI.catFull - catPivot)
            return Swift.min(1.0, Swift.max(0.0, raw))
        }

        /// The stronger of the two down-bucket anticipations — used by the read
        /// line so the "loading up for the deep ball" call fires off whichever
        /// bucket the coach has been leaning on.
        func anticipationPeak(of concept: OffenseTendency?) -> Double {
            Swift.max(anticipation(of: concept, down: 1), anticipation(of: concept, down: 3))
        }

        // MARK: Exact-call layer

        /// How many of the last `exactWindow` snaps ran THIS exact call
        /// (post-record) — drives the read-line "sitting on the toss" trigger.
        func recentCount(of call: OffensivePlayCall) -> Int {
            exactRing.suffix(AdaptiveOpponentAI.exactWindow).filter { $0 == call }.count
        }

        /// Repeat index of `call` INCLUDING the current (about-to-snap) call:
        /// 1 on a fresh call, ramping to `exactWindow`. Reads the last
        /// `exactWindow − 1` recorded calls + 1, so a switch drops it to 1
        /// immediately (punish 0) and the old call decays out within ~2 snaps.
        func repeatCount(for call: OffensivePlayCall) -> Int {
            let recent = exactRing.suffix(AdaptiveOpponentAI.exactWindow - 1)
            return Swift.min(AdaptiveOpponentAI.exactWindow, recent.filter { $0 == call }.count + 1)
        }

        /// The exact-call punish on the three resolution levers, bounded by each
        /// lever's own cap. 0 on a first/switched call; bites from the 2nd.
        func exactPunish(for call: OffensivePlayCall)
            -> (pass: Double, runYard: Double, runStuff: Double) {
            let over = Double(repeatCount(for: call) - 1)   // 0…3
            let pass = Swift.min(over * AdaptiveOpponentAI.exactStepPassMalus,
                                 AdaptiveOpponentAI.exactPassCap)
            let runYard = Swift.min(over * AdaptiveOpponentAI.exactStepRunYard,
                                    AdaptiveOpponentAI.exactRunYardCap)
            let runStuff = Swift.min(over * AdaptiveOpponentAI.exactStepRunStuff,
                                     AdaptiveOpponentAI.exactRunStuffCap)
            return (pass, runYard, runStuff)
        }

        // MARK: Counter-open (mirror)

        /// The bonus the CALLED concept earns for attacking whatever the defense
        /// is currently anticipating (Layer B counterplay). Scans every
        /// currently-anticipated concept; if the called concept is in that read's
        /// open set, the caller earns a positive shift scaled by the strongest
        /// such anticipation. `suppressDeepCounter` zeroes the PASS bonus for a
        /// deep/PA call so it never stacks on the existing `paKey` deep punish.
        func counterOpen(forCalled concept: OffenseTendency, down: Int,
                         suppressDeepCounter: Bool) -> (pass: Double, run: Double) {
            var best = 0.0
            for anticipated in OffenseTendency.allCases where anticipated != concept {
                let ant = anticipation(of: anticipated, down: down)
                guard ant > 0 else { continue }
                if AdaptiveOpponentAI.counterConcepts(for: anticipated).contains(concept) {
                    best = Swift.max(best, ant)
                }
            }
            guard best > 0 else { return (0, 0) }
            let isDeepShot = (concept == .deepPass || concept == .playAction)
            let pass = (isDeepShot && suppressDeepCounter)
                ? 0
                : AdaptiveOpponentAI.counterOpenPassBonus * best
            let run = AdaptiveOpponentAI.counterOpenRunBonus * best
            return (pass, run)
        }
    }

    // MARK: - Bounded in-play key modifiers (shared free functions)
    //
    // All four are pure, bounded, and mean-neutral at zero intensity, so an
    // un-keyed defense changes nothing. They are the ONLY levers Layer A adds
    // to `PlaySimulator`'s resolution — no hidden malus.
    //
    // The two RUN levers are harness-dialed from the design's start points
    // (yardBite 1.6, stuff 0.14): applied literally they stacked to ~1.7 ypc at
    // full key (below the design's own ~3-ypc-keyed target) AND pushed the
    // balanced-control over the line. Dialed to 1.1 / 0.08 a fully keyed run
    // lands ~2.85 ypc (mid of the 2.5–3.5 band) while balanced play is spared.

    /// Yards shaved off the run mean at key intensity `i` (up to −1.1 yд).
    static func runKeyYardBite(_ i: Double) -> Double { i * 1.1 }
    /// Extra stuff (≤ short gain) probability at intensity `i` (up to +0.08).
    static func runKeyStuffBonus(_ i: Double) -> Double { i * 0.08 }
    /// DEEP-TALENT rebase: the keyed-PA punish base is now the 70/70-baseline
    /// bonus (scale 1.0); the deep-composite scaler at the PlaySimulator call
    /// sites supplies the talent spread (an elite deep duo torches a keyed box,
    /// a weak one cannot). Was 0.18 flat → 0.035 base × deepPunishScale.
    static func paKeyCompletion(_ i: Double) -> Double { i * 0.035 }
    /// Extra air yards on the play-action punish vs a keyed box (baseline; scaled
    /// by deepPunishScale at the call site). Was 8.0 flat → 2.0 base.
    static func paKeyBigPlay(_ i: Double) -> Double { i * 2.0 }

    // MARK: - Play-Memory tuning (Layer B — coached path)
    //
    // Start points from the design; the harness dials them within the authorized
    // bands. Every one is a bounded, mean-neutral SHIFT: at 0 anticipation / a
    // never-repeated call all deltas are 0, so a mixed caller and the sim path
    // are untouched.

    // CATEGORY layer
    static let catPivotBase           = 0.42   // neutral share ≈0.14 ⇒ mixed caller never triggers
    static let catFull                = 0.72   // share at full anticipation
    static let catAlphaBase           = 0.28   // ~5–7 snap ramp; persona/grade scale it
    // Harness-dialed 0.14→0.13 (band 0.10–0.20): 0.13 lands category-spam deep
    // completion ~36% (design's 35–38% target) — a 0.14 shift overshot to ~35 flat.
    static let catPassCompletionMalus = 0.13   // max completion malus at full anticipation
    static let catRunYardBite         = 0.60   // max extra yд bite on an anticipated run flavor
    // Harness-dialed 0.04→0.03 (band 0.02–0.07): the stuff channel is a lean, not
    // the wall — trimmed so a spammed INSIDE run floors ≥ ~2.2 ypc (runGrandBiteCap
    // owns the yard bite; over-large stuff bonuses removed the breakaway tail and
    // dropped a keyed run under the fairness floor).
    static let catRunStuffBonus       = 0.03   // max extra stuff probability at full anticipation

    // EXACT-CALL layer (coached only)
    static let exactWindow            = 4      // decaying ring width (incl. current)
    static let exactStepPassMalus     = 0.07   // per repeat over 1
    static let exactPassCap           = 0.20
    static let exactStepRunYard       = 0.70
    static let exactRunYardCap        = 2.00
    static let exactStepRunStuff      = 0.03
    static let exactRunStuffCap       = 0.06   // harness-dialed 0.09→0.06 (same run-floor reason)
    static let exactHintRepeat        = 3      // read line fires on the 3rd identical call

    // COMBINED CAPS (fairness — a lean, never a wall)
    static let passTotalMalusCap      = 0.24   // category+exact per pass depth
    static let runGrandBiteCap        = 1.80   // runKey (≤1.1) + category + exact, TOTAL adaptive bite

    // COUNTER-OPEN (mirror)
    static let counterOpenPassBonus   = 0.12   // deep entry suppressed when paKey active
    static let counterOpenRunBonus    = 0.70
    static let catHintAnticipation    = 0.50   // category read-line firing threshold

    /// Category anticipation PIVOT — reuses the exact grade shape the read line
    /// already uses (`scaledThreshold`), then the DC persona's `thresholdOffset`
    /// (aggressive −0.06 keys sooner, conservative +0.08 slower). Grade elite
    /// (100) −0.10, poor (0) +0.10. Persona enters ONLY through `thresholdOffset`
    /// (a Double), keeping this decoupled from `CoordinatorPersona`.
    static func catPivot(thresholdOffset: Double, grade: Int) -> Double {
        catPivotBase + (0.10 - 0.20 * grade01(grade)) + thresholdOffset
    }

    /// Category EWMA ALPHA (ramp SPEED) — a high-IQ / aggressive DC keys sooner
    /// (lower pivot) AND ramps faster (higher alpha); a stubborn conservative DC
    /// does both slower. `adapt01` blends grade with the sign of the persona
    /// offset. Bounded 0.18…0.45 so timing moves but the bite ceiling never does.
    static func catAlpha(thresholdOffset: Double, grade: Int) -> Double {
        let bias = thresholdOffset < 0 ? 0.2 : (thresholdOffset > 0 ? -0.2 : 0.0)
        let adapt01 = Swift.min(1.0, Swift.max(0.0, grade01(grade) + bias))
        return Swift.min(0.45, Swift.max(0.18, catAlphaBase * (1 + 0.6 * adapt01)))
    }
}
