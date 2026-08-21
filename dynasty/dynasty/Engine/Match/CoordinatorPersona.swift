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
//
// `stablePersonaPick` lives on `HCPersona.swift` (Domain/Models/Coach) because
// the head-coach persona is reachable from the quick sim and therefore from the
// balance harness, which stages `GameSimulator.swift` verbatim and does not —
// and should not — carry this file's playbook/call-sheet dependency graph. One
// hash helper, one definition, used by all three personas.

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
    ///
    /// F-38(a): `.conservative` and `.balanced` were **0.0**, and `derive` maps
    /// `base43 → {balanced, conservative}`, `tampa2 → conservative` and
    /// `cover3 → {conservative, balanced}` — so three of the seven scheme
    /// buckets, covering the most common defensive systems in football, produced
    /// a coordinator with a literally zero error rate. This was the shipped
    /// game's ONLY modelled AI decision error, and 40 % of coordinators were
    /// exempt from it.
    ///
    /// The floor is 0.05, not the aggressive DC's 0.18, because the two errors
    /// are different animals: the aggressive DC's is over-commitment, and it is
    /// supposed to be his defining flaw. A careful coordinator still guesses
    /// wrong about one snap in twenty, and that is what 0.05 buys.
    ///
    /// Trades against: how often the AI defence hands the player a free window.
    /// Because the counter acts purely through modifiers that already exist
    /// (`AdaptiveOpponentAI`'s package biases), a wrong counter is automatically
    /// a bad-but-legal call — it opens no new balance surface, which is why the
    /// floor could be added without a new fairness cap.
    var misreadChance: Double {
        switch self {
        case .aggressive: return 0.18
        case .exotic:     return 0.08
        case .conservative, .balanced: return 0.05
        }
    }

    /// F-38(b): the misread rate for a coordinator of a given grade.
    ///
    /// `basePersonaMisread + max(0, (70 − grade) / 100 × 0.15)` — +0.045 at grade
    /// 40, +0 at grade 90. The sign is the whole point: **coach quality buys
    /// FEWER mistakes**, which is what coach quality actually buys. Every other
    /// coaching channel in the engine already works this way (`CoachingModifiers`
    /// is centred at 70 and symmetric), and an error model in which a better
    /// coordinator errs more would be an imperfection model pointing backwards.
    ///
    /// One-sided by design: `max(0, …)` means a grade-90 DC gets the persona's
    /// own rate and no discount below it. A coordinator who never guesses wrong
    /// is not a better coach, he is a different game.
    ///
    /// Trades against: the aggregate error budget. §4.3.6's guardrail is ~2
    /// decision errors per coach per game; at ~28 defensive snaps where a counter
    /// is even rolled, a floored-and-scaled balanced DC at grade 40 lands near
    /// 0.095, i.e. under three — and roughly half of those errors are
    /// over-aggression that sometimes helps the AI anyway.
    static func effectiveMisread(base: Double, grade: Int) -> Double {
        base + max(0, Double(70 - grade) / 100.0 * 0.15)
    }

    // MARK: Base-call shading (live AI defense only)

    /// Persona-shaded version of the base situational package. Uses live RNG —
    /// the engine pre-rolls this once per snap so the pre-snap preview and the
    /// actual play always agree. Never called for the red-zone sellout or the
    /// late-lead prevent shell (the engine guards those).
    ///
    /// The persona decides *how often* the base fabric gets overridden; the
    /// active SCHEME decides *with what*. Rates track the scheme's own
    /// `Playbook.mix` (a press-man staff blitzes and plays man about twice as
    /// often as a Tampa 2 staff) and every override is a named call off that
    /// scheme's call sheet, so the pressure a 3-4 defense brings is its Fire
    /// Zone and the pressure a press-man defense brings is Cover 0.
    /// A schemeless coordinator falls back to the pre-expansion behavior
    /// exactly — same rates, same dimension-only mutations.
    func shadedDefense(
        base: DefensivePackage,
        distance: Int,
        scheme: DefensiveScheme?
    ) -> DefensivePackage {
        var package = base
        let mix = DCPersona.mix(for: scheme)
        switch self {
        case .balanced:
            // The balanced DC IS his scheme's base fabric: `derive` only ever
            // pairs `.balanced` with the two zone-first schemes (`cover3`,
            // `base43`), whose identity is the sound Cover 3 / two-high look
            // the engine already handed us. Nothing to shade, no RNG consumed.
            return base
        case .aggressive:
            // Pressure on standard downs — the scheme's own heat, at its own
            // rate (0.22 Tampa 2 → 0.48 press man blitz share).
            if package.blitz == .noBlitz,
               Double.random(in: 0..<1) < DCPersona.pressureChance(mix) {
                if let call = DCPersona.pressureCall(distance: distance, scheme: scheme) {
                    return DCPersona.shade(call, over: package)
                }
                package.blitz = Double.random(in: 0..<1) < 0.35 ? .doubleAGap : .lbBlitz
            }
            // Man leanings over the zone fabric, at the scheme's man share.
            if package.coverage == .cover3,
               Double.random(in: 0..<1) < DCPersona.manRotationChance(mix) {
                package.coverage = .manToMan
            }
        case .conservative:
            // Call off situational pressure, drop into a deep shell.
            if package.blitz != .noBlitz, Double.random(in: 0..<1) < 0.60 {
                package.blitz = .noBlitz
                if distance >= 7 {
                    return DCPersona.shade(
                        DCPersona.softShellCall(scheme: scheme), over: package)
                }
            } else if distance >= 7, package.blitz == .noBlitz,
                      Double.random(in: 0..<1) < 0.40 {
                // Nothing to call off — but on a passing down the conservative
                // DC still checks into HIS OWN shell instead of the generic
                // quarters/dime the situational logic hands every defense: a
                // Tampa 2 staff plays Tampa 2, a 4-3 staff plays its Cloud 2.
                // The personnel grouping (dime on 3rd-&-long) is preserved.
                return DCPersona.shade(
                    DCPersona.softShellCall(scheme: scheme), over: package)
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

    // MARK: Scheme weights

    /// The mix a coordinator with no named scheme trends to — the neutral
    /// middle, chosen so every rate below reproduces the pre-expansion
    /// constants (0.30 pressure / 0.35 man) for a schemeless staff.
    static let neutralMix = Playbook.DefensiveMix(
        manShare: 0.35, blitzShare: 0.35, twoHighShare: 0.35
    )

    static func mix(for scheme: DefensiveScheme?) -> Playbook.DefensiveMix {
        scheme.map({ Playbook.mix(for: $0) }) ?? neutralMix
    }

    /// Chance the aggressive DC adds pressure to a standard down: the old flat
    /// 0.30 at the neutral 0.35 blitz share, tracking the scheme one-for-one
    /// and bounded so no scheme blitzes half its standard downs away.
    private static func pressureChance(_ mix: Playbook.DefensiveMix) -> Double {
        min(0.45, max(0.12, 0.30 + (mix.blitzShare - 0.35)))
    }

    /// Chance the aggressive DC rotates the zone fabric to man — simply the
    /// scheme's own man share (0.15 Tampa 2 … 0.72 press man), bounded.
    private static func manRotationChance(_ mix: Playbook.DefensiveMix) -> Double {
        min(0.60, max(0.08, mix.manShare))
    }

    // MARK: Scheme call pools

    /// Apply a named call as the shade, but never downgrade a FRONT the
    /// situational logic deliberately chose. The engine's base package sets
    /// `.base` on a neutral down and something specific when the situation
    /// (or a read) demands it: the short-yardage / keyed-run Bear box the
    /// player is meant to SEE, or the 3rd-&-long dime personnel. The persona
    /// owns the coverage and the pressure; the situation owns the personnel.
    private static func shade(
        _ call: DefensiveCall,
        over base: DefensivePackage
    ) -> DefensivePackage {
        var package = call.package
        if base.front != .base { package.front = base.front }
        return package
    }

    /// The pressure this scheme actually owns, preferring its signature heat
    /// (entered twice ≈ 2× draw weight). `nil` for a schemeless coordinator or
    /// a playbook with no pressure call — the caller then shades the blitz
    /// dimension exactly as it did before schemes existed.
    private static func pressureCall(
        distance: Int,
        scheme: DefensiveScheme?
    ) -> DefensiveCall? {
        guard let scheme else { return nil }
        let pool = longYardageFiltered(
            Playbook.installedCalls(for: scheme).filter { $0.package.blitz != .noBlitz },
            distance: distance
        )
        guard !pool.isEmpty else { return nil }
        let signature = pool.filter { Playbook.isSignature($0, of: scheme) }
        return (pool + signature).randomElement()
    }

    /// The long-yardage shell a conservative DC drops into: the scheme's own
    /// two-high, extra-DB coverage call, signature preferred. Dime is the
    /// fallback — Cover 4 out of six DBs, i.e. exactly the cover4 + dime
    /// package this branch produced before schemes existed.
    private static func softShellCall(scheme: DefensiveScheme?) -> DefensiveCall {
        guard let scheme else { return .dimePackage }
        let twoHigh: Set<DefensivePlayCall> = [.cover2, .cover4, .tampa2, .cover6]
        let extraDB: Set<DefensivePlayCall> = [.nickel, .bigNickel, .dime]
        let pool = Playbook.installedCalls(for: scheme).filter {
            $0.package.blitz == .noBlitz
                && twoHigh.contains($0.package.coverage)
                && extraDB.contains($0.package.front)
        }
        guard !pool.isEmpty else { return .dimePackage }
        let signature = pool.filter { Playbook.isSignature($0, of: scheme) }
        return (pool + signature).randomElement() ?? .dimePackage
    }

    /// The exotic pool: the shared Double A-Gap / Zone Blitz / Bear trio plus
    /// whatever exotic heat the scheme adds (`Playbook.exoticAdditions` — the
    /// Fire Zone for a 3-4, the creeper for a multiple front, Cover 0 for press
    /// man), preferring calls the coordinator's playbook installs.
    private static func exoticPackage(
        distance: Int,
        scheme: DefensiveScheme?
    ) -> DefensivePackage {
        var pool: [DefensiveCall] = [.doubleAGap, .zoneBlitz, .bearFront]
        if let scheme { pool += Playbook.exoticAdditions(for: scheme) }
        pool = longYardageFiltered(pool, distance: distance)
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        return ((installed.isEmpty ? pool : installed).randomElement() ?? .zoneBlitz).package
    }

    /// Long-yardage sanity for a pressure/exotic pool: once the offense HAS to
    /// throw, the heavy run fronts (Bear, Goal Line) and the zero-help gamble
    /// (Cover 0 — committing to no deep help on 3rd-and-long is a call, not a
    /// surprise) both come off the sheet. Never empties the pool.
    private static func longYardageFiltered(
        _ pool: [DefensiveCall],
        distance: Int
    ) -> [DefensiveCall] {
        guard distance >= 7 else { return pool }
        let filtered = pool.filter {
            $0.package.front != .bear
                && $0.package.front != .goalLine
                && $0.package.coverage != .cover0
        }
        return filtered.isEmpty ? pool : filtered
    }

    // MARK: Shell audible (presentation surface — see OCPersona.preferredAudible)

    /// The DC's own pick out of the shell-audible strip
    /// (`DefensivePlayCall.audibleShells`, already filtered to exclude the
    /// current shell). Deterministic — no RNG — so the chip the UI stars is
    /// the check this coordinator would actually make.
    ///
    /// Aggressive DCs and high-man schemes rotate INTO man; conservative DCs
    /// and two-high schemes rotate into a two-high zone; everyone else keeps
    /// the sound single-high fabric.
    func preferredShellAudible(
        from options: [DefensivePlayCall],
        scheme: DefensiveScheme?
    ) -> DefensivePlayCall? {
        guard !options.isEmpty else { return nil }
        let mix = DCPersona.mix(for: scheme)
        let order: [DefensivePlayCall]
        if self == .aggressive || mix.manShare >= 0.45 {
            order = [.manToMan, .cover1, .cover6, .cover2, .tampa2, .cover3, .cover4]
        } else if self == .conservative || mix.twoHighShare >= 0.45 {
            order = [.tampa2, .cover2, .cover4, .cover6, .cover3, .cover1, .manToMan]
        } else {
            order = [.cover3, .cover6, .cover4, .cover2, .tampa2, .cover1, .manToMan]
        }
        return order.first(where: options.contains) ?? options.first
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

    /// F-38(c): chance a rolled offensive counter attacks the WRONG defensive
    /// tendency. `OCPersona` had **no misread field at all**, so the AI offense
    /// never once misread the player's defensive tendency anywhere in the game —
    /// the DC could be wrong, the OC could not.
    ///
    /// The rates track how much each identity is guessing in the first place.
    /// The Air Raid is a system built on pre-snap reads and one-on-one bets, so
    /// it is wrong most often; ground-and-pound barely reads at all, because it
    /// intends to run the same play regardless, and a call that ignores the
    /// defence cannot misread it.
    ///
    /// Applied exactly as the DC's is, through `AdaptiveOpponentAI`'s existing
    /// package modifiers — so a wrong counter is a bad-but-legal call and adds
    /// no new balance surface.
    ///
    /// Trades against: the AI offense's efficiency against a player who has
    /// shown a tendency. Kept at or below the DC's floor-to-0.15 range so the
    /// combined per-game error budget stays inside §4.3.6's ~2-per-coach cap.
    var misreadChance: Double {
        switch self {
        case .airRaid:        return 0.15
        case .westCoast:      return 0.08
        case .groundAndPound: return 0.05
        case .balanced:       return 0.05
        }
    }

    // MARK: Signature calls (live AI offense only)

    /// Share of AI offensive snaps the persona overrides the base logic with
    /// an identity play. This is the fallback for a coordinator with NO named
    /// scheme; a coordinator who runs one uses his scheme's own share instead
    /// (`Playbook.signatureShare` — 0.28 pro passing … 0.38 power run/option),
    /// which is why a `.balanced` persona still shows an identity as long as
    /// he runs a real system. 0 = pure base logic.
    var signatureChance: Double {
        switch self {
        case .groundAndPound: return 0.35
        case .airRaid:        return 0.30
        case .westCoast:      return 0.30
        case .balanced:       return 0.0
        }
    }

    /// The persona's identity plays for this distance, used ONLY when the
    /// coordinator runs no named scheme (a real scheme supplies its own pool
    /// via `Playbook.signaturePool`). Empty = the situation doesn't fit the
    /// identity — stay on base logic for this snap.
    private func personaPool(distance: Int) -> [OffensivePlayCall] {
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

    /// Whether a call fits the persona's temperament. This is the ONLY thing
    /// the persona does inside a real scheme's identity pool: a favoured call
    /// is entered twice, so it is drawn ~2× as often without ever locking the
    /// scheme's other identity plays out. The scheme picks the sheet, the
    /// persona picks off it.
    private func favours(_ call: OffensivePlayCall) -> Bool {
        switch self {
        case .groundAndPound:
            return call.isRun
        case .airRaid:
            let depth = call.simulatorHint.passDepth
            return depth == .deep || depth == .medium
        case .westCoast:
            return call.isPass && call.simulatorHint.passDepth == .short
        case .balanced:
            return false
        }
    }

    /// One pre-rolled signature call for the next AI offensive snap, drawn from
    /// the ACTIVE SCHEME's identity pool (`Playbook.signaturePool` — the
    /// distance-banded lists from the playbook catalog) at the scheme's own
    /// signature share, biased by the persona and filtered for situational
    /// sanity (no deep shots near the goal line). `nil` = base logic.
    ///
    /// Both ground schemes deliberately return an EMPTY pool in true passing
    /// downs — a power-run identity has no answer to 3rd-and-12, and forcing
    /// one would be worse than falling back to the situational logic.
    ///
    /// Uses live RNG — the engine rolls this once per snap, gated on the
    /// player having made at least one explicit call (quick-sim parity).
    func rollSignatureCall(
        distance: Int,
        yardsToEndzone: Int,
        scheme: OffensiveScheme?
    ) -> OffensivePlayCall? {
        let share = scheme.map({ Playbook.signatureShare(for: $0) }) ?? signatureChance
        guard share > 0, Double.random(in: 0..<1) < share else { return nil }
        var pool = scheme.map { Playbook.signaturePool(for: $0, distance: distance) }
            ?? personaPool(distance: distance)
        if yardsToEndzone < 25 {
            pool.removeAll { $0.simulatorHint.passDepth == .deep || $0 == .playActionDeep }
        }
        guard !pool.isEmpty else { return nil }
        let installed = pool.filter { $0.isInPlaybook(of: scheme) }
        let sheet = installed.isEmpty ? pool : installed
        return (sheet + sheet.filter(favours)).randomElement()
    }

    // MARK: Audible mapping (presentation surface)

    /// The coach's own pick out of an audible strip. The options are already
    /// filtered to the current formation family and the installed playbook by
    /// `OffensivePlayCall.audibleOptions(installed:)`; this only RANKS them,
    /// deterministically (no RNG), so the chip the UI stars is the check this
    /// coordinator would actually make and it never changes under the player's
    /// finger.
    ///
    /// Preference order:
    ///  1. a call the pre-snap coverage read says beats the shell shown
    ///     (`OffensivePlayCall.goodAgainst`),
    ///  2. one of the active scheme's signature calls — its identity check,
    ///  3. a call this persona's temperament favours,
    ///  4. the first option on the strip (call-sheet order).
    func preferredAudible(
        from options: [OffensivePlayCall],
        scheme: OffensiveScheme?,
        against coverage: DefensivePlayCall?
    ) -> OffensivePlayCall? {
        guard !options.isEmpty else { return nil }
        if let coverage, let beater = options.first(where: { $0.goodAgainst(coverage) }) {
            return beater
        }
        if let scheme, let signature = options.first(where: { Playbook.isSignature($0, of: scheme) }) {
            return signature
        }
        return options.first(where: favours) ?? options.first
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
