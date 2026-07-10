import Foundation

// MARK: - Coordinator Play-Calling Personas (R33, live games only)
//
// The opponent's DC/OC each get a play-calling PERSONA layered on top of the
// base situational AI (`LiveGameEngine.aiDefensivePackage` / `aiOffensiveCall`)
// and the R12 adaptive core (`AdaptiveOpponentAI`):
//
//   • DC: Aggressive (blitz-heavy man looks, keys fast, over-reacts — counters
//     come harder but can target the WRONG tendency), Conservative (zone
//     shells, rare blitzes, slow to adapt), Balanced (today's behavior),
//     Exotic (unusual packages — Double A-Gap, Zone Blitz, Bear — far more
//     often).
//   • OC: Ground & Pound / Air Raid / West Coast / Balanced — a persona-
//     weighted "signature call" share mixed into the base call logic, plus a
//     mild adaptation-speed shade.
//
// Derivation is DETERMINISTIC: primarily from the coach's scheme field, with
// a stable Coach-id hash breaking two-way buckets (and picking outright when
// the coach has no scheme). The same coach always scouts and plays the same
// way — Week Prep (GamePlanView) shows exactly the persona the live game uses.
//
// Quick-sim parity: nothing here is reachable from `GameSimulator.simulate`,
// and `LiveGameEngine` only rolls persona randomness once the player has made
// at least one explicit live call (nil-argument games consume no RNG).

// MARK: - Deterministic pick helper

/// Stable pick from `options` driven by the coach's UUID — same coach, same
/// persona, every game and every screen.
private func stablePersonaPick<T>(_ options: [T], id: UUID) -> T {
    let hash = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    let index = ((hash % options.count) + options.count) % options.count
    return options[index]
}

// MARK: - Defensive Coordinator Persona

enum DCPersona: String, CaseIterable {
    case aggressive   = "Aggressive"
    case conservative = "Conservative"
    case balanced     = "Balanced"
    case exotic       = "Exotic"

    var displayName: String { rawValue }

    // MARK: Derivation

    /// Deterministic persona for a DC: scheme is the primary signal, the
    /// stable id hash breaks two-way buckets (and decides outright when the
    /// coach runs no named scheme).
    static func derive(for coach: Coach) -> DCPersona {
        switch coach.defensiveScheme {
        case .pressMan:           return .aggressive
        case .base34:             return stablePersonaPick([.aggressive, .exotic], id: coach.id)
        case .base43:             return stablePersonaPick([.balanced, .conservative], id: coach.id)
        case .tampa2:             return .conservative
        case .cover3:             return stablePersonaPick([.conservative, .balanced], id: coach.id)
        case .multiple, .hybrid:  return .exotic
        case nil:                 return stablePersonaPick(DCPersona.allCases, id: coach.id)
        }
    }

    // MARK: Adaptation scaling (feeds AdaptiveOpponentAI via LiveGameEngine)

    /// Added to the grade-scaled tendency threshold: negative = keys sooner.
    var thresholdOffset: Double {
        switch self {
        case .aggressive:   return -0.06
        case .conservative: return  0.08
        case .balanced:     return  0.0
        case .exotic:       return -0.02
        }
    }

    /// Multiplier on the grade-scaled counter share (clamped by the engine).
    var counterShareMultiplier: Double {
        switch self {
        case .aggressive:   return 1.3
        case .conservative: return 0.6
        case .balanced:     return 1.0
        case .exotic:       return 1.1
        }
    }

    /// Over-reaction: chance a rolled counter targets the WRONG tendency —
    /// the aggressive DC sells out against a read that isn't there.
    var misreadChance: Double {
        switch self {
        case .aggressive: return 0.18
        case .exotic:     return 0.08
        case .conservative, .balanced: return 0.0
        }
    }

    // MARK: Base-call shading (live AI defense only)

    /// Persona-shaded version of the base situational package. Uses live RNG —
    /// the engine pre-rolls this once per snap so the pre-snap preview and the
    /// actual play always agree. Never called for the red-zone sellout or the
    /// late-lead prevent shell (the engine guards those).
    func shadedDefense(
        base: DefensivePackage,
        distance: Int,
        scheme: DefensiveScheme?
    ) -> DefensivePackage {
        var package = base
        switch self {
        case .balanced:
            return base
        case .aggressive:
            // Pressure on standard downs, man leanings over the zone fabric.
            if package.blitz == .noBlitz, Double.random(in: 0..<1) < 0.30 {
                package.blitz = Double.random(in: 0..<1) < 0.35 ? .doubleAGap : .lbBlitz
            }
            if package.coverage == .cover3, Double.random(in: 0..<1) < 0.35 {
                package.coverage = .manToMan
            }
        case .conservative:
            // Call off situational pressure, drop into a deep shell.
            if package.blitz != .noBlitz, Double.random(in: 0..<1) < 0.60 {
                package.blitz = .noBlitz
                if distance >= 7 {
                    package.coverage = .cover4
                    package.front = .dime
                }
            }
        case .exotic:
            // Unusual packages far more often than anyone else calls them.
            if Double.random(in: 0..<1) < 0.25 {
                return DCPersona.exoticPackage(distance: distance, scheme: scheme)
            }
            if package.blitz == .noBlitz, Double.random(in: 0..<1) < 0.12 {
                package.blitz = .lbBlitz
            }
        }
        return package
    }

    /// The exotic pool: Double A-Gap, Zone Blitz, Bear — preferring calls the
    /// coordinator's playbook installs, and never Bear on long yardage.
    private static func exoticPackage(
        distance: Int,
        scheme: DefensiveScheme?
    ) -> DefensivePackage {
        var pool: [DefensiveCall] = [.doubleAGap, .zoneBlitz, .bearFront]
        if distance >= 7 { pool.removeAll { $0 == .bearFront } }
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        return ((installed.isEmpty ? pool : installed).randomElement() ?? .zoneBlitz).package
    }

    // MARK: Presentation

    /// Week Prep scouting line (GamePlanView opponent panel).
    var scoutingBlurb: String {
        switch self {
        case .aggressive:   return "Blitz-heavy man looks. Adapts fast, over-commits."
        case .conservative: return "Zone shells, rare blitzes. Slow to adjust."
        case .balanced:     return "Sound, situational calls on every down."
        case .exotic:       return "Unusual pressure packages — hard to prepare for."
        }
    }

    /// Pre-kickoff booth intel line for the broadcast feed.
    func broadcastIntro(abbr: String) -> String {
        switch self {
        case .aggressive:   return "\(abbr)'s DC lives to blitz — keep your protections sharp"
        case .conservative: return "\(abbr)'s DC plays it safe: zone shells and rally tackling"
        case .balanced:     return "\(abbr)'s DC calls it straight — a sound, situational game"
        case .exotic:       return "\(abbr)'s DC loves exotic pressure — expect the unexpected"
        }
    }
}

// MARK: - Offensive Coordinator Persona

enum OCPersona: String, CaseIterable {
    case groundAndPound = "Ground & Pound"
    case airRaid        = "Air Raid"
    case westCoast      = "West Coast"
    case balanced       = "Balanced"

    var displayName: String { rawValue }

    // MARK: Derivation

    /// Deterministic persona for an OC — scheme first, stable id hash for
    /// two-way buckets and schemeless coaches.
    static func derive(for coach: Coach) -> OCPersona {
        switch coach.offensiveScheme {
        case .powerRun:   return .groundAndPound
        case .option:     return stablePersonaPick([.groundAndPound, .balanced], id: coach.id)
        case .airRaid:    return .airRaid
        case .spread:     return stablePersonaPick([.airRaid, .balanced], id: coach.id)
        case .westCoast:  return .westCoast
        case .rpo:        return stablePersonaPick([.westCoast, .balanced], id: coach.id)
        case .shanahan:   return stablePersonaPick([.balanced, .groundAndPound], id: coach.id)
        case .proPassing: return stablePersonaPick([.balanced, .westCoast], id: coach.id)
        case nil:         return stablePersonaPick(OCPersona.allCases, id: coach.id)
        }
    }

    // MARK: Adaptation scaling (mild — the OC persona is mostly identity)

    /// Added to the grade-scaled defensive-tendency thresholds: the stubborn
    /// run-first OC keys later, the Air Raid OC pounces a touch sooner.
    var adaptThresholdOffset: Double {
        switch self {
        case .groundAndPound: return  0.04
        case .airRaid:        return -0.02
        case .westCoast, .balanced: return 0.0
        }
    }

    /// Multiplier on the grade-scaled counter share (clamped by the engine).
    var counterShareMultiplier: Double {
        switch self {
        case .groundAndPound: return 0.85
        case .airRaid:        return 1.1
        case .westCoast, .balanced: return 1.0
        }
    }

    // MARK: Signature calls (live AI offense only)

    /// Share of AI offensive snaps the persona overrides the base logic with
    /// an identity play (0 = pure base logic, today's behavior).
    var signatureChance: Double {
        switch self {
        case .groundAndPound: return 0.35
        case .airRaid:        return 0.30
        case .westCoast:      return 0.30
        case .balanced:       return 0.0
        }
    }

    /// The persona's identity plays for this distance. Empty = the situation
    /// doesn't fit the identity — stay on base logic for this snap.
    private func signaturePool(distance: Int) -> [OffensivePlayCall] {
        switch self {
        case .groundAndPound:
            guard distance < 8 else { return [] }          // no runs into long yardage
            return distance <= 2
                ? [.insideRun, .dive, .toss]
                : [.insideRun, .outsideRun, .counter, .toss]
        case .airRaid:
            guard distance > 2 else { return [] }          // short yardage: base logic
            return [.seam, .dig, .post, .corner, .goRoute, .flood, .mesh]
        case .westCoast:
            return distance <= 2
                ? [.slant, .quickOut, .flat]
                : [.slant, .quickOut, .drag, .stick, .flat, .curl, .screen]
        case .balanced:
            return []
        }
    }

    /// One pre-rolled signature call for the next AI offensive snap, filtered
    /// for situational sanity (no deep shots near the goal line) and
    /// preferring the coordinator's installed playbook. `nil` = base logic.
    /// Uses live RNG — the engine rolls this once per snap.
    func rollSignatureCall(
        distance: Int,
        yardsToEndzone: Int,
        scheme: OffensiveScheme?
    ) -> OffensivePlayCall? {
        guard signatureChance > 0, Double.random(in: 0..<1) < signatureChance else { return nil }
        var pool = signaturePool(distance: distance)
        if yardsToEndzone < 25 {
            pool.removeAll { $0.simulatorHint.passDepth == .deep || $0 == .playActionDeep }
        }
        guard !pool.isEmpty else { return nil }
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        return (installed.isEmpty ? pool : installed).randomElement()
    }

    // MARK: Presentation

    /// Week Prep scouting line (GamePlanView opponent panel).
    var scoutingBlurb: String {
        switch self {
        case .groundAndPound: return "Run-first identity. Wants to wear you down."
        case .airRaid:        return "Pass-happy — shots downfield all game."
        case .westCoast:      return "Quick timing throws underneath."
        case .balanced:       return "Even mix — takes what the defense gives."
        }
    }

    /// Pre-kickoff booth intel line for the broadcast feed.
    func broadcastIntro(abbr: String) -> String {
        switch self {
        case .groundAndPound: return "\(abbr)'s OC wants to ground and pound — the run is coming"
        case .airRaid:        return "\(abbr)'s OC runs the Air Raid — the ball is going up"
        case .westCoast:      return "\(abbr)'s OC dinks and dunks — quick game, rhythm throws"
        case .balanced:       return "\(abbr)'s OC keeps the sheet balanced — nothing comes free"
        }
    }
}
