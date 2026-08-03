import Foundation

// MARK: - Playbook

/// The authoritative playbook catalog.
///
/// Every scheme-identity question in the game routes through here:
///
/// * **Install lists** — which calls a scheme's playbook actually contains.
///   `OffensivePlayCall.schemes` and `DefensiveCall.schemes` are *inverted*
///   from these tables, so the install list is the single source of truth and
///   the per-play membership array can never drift out of sync with it.
/// * **Signature calls** — the 3-4 plays that define the scheme's identity.
/// * **Call-tendency weights** — the ordered preference lists an AI
///   coordinator picks from for a given situation, plus the share of snaps a
///   coordinator spends inside his signature pool.
/// * **Defensive mix** — the man / blitz / two-high rates a defensive scheme
///   trends toward, and the exotic calls it adds to its pressure pool.
///
/// Nothing in here is persisted. The tables are pure static data keyed by
/// scheme, so they can be retuned freely without touching save compatibility
/// (only `OffensivePlayCall.rawValue` is save data — see the persistence
/// contract comment on that enum).
///
/// A play that appears in NO scheme's install list is still fully callable —
/// the call sheet renders it dimmed with a "practice this week" affordance, the
/// AI simply never reaches for it, and `MatchupResolver.bustRoll` charges the
/// existing out-of-playbook familiarity penalty.
enum Playbook {

    // ==================================================================
    // MARK: - Offense: install lists
    // ==================================================================

    /// Situational calls every offense owns regardless of identity.
    static let universalOffensivePlays: [OffensivePlayCall] = [.qbSneak, .spike, .kneel]

    /// The plays a scheme's playbook installs (excluding the universal three).
    static func installedPlays(for scheme: OffensiveScheme) -> [OffensivePlayCall] {
        offenseInstall[scheme] ?? []
    }

    /// The scheme identity plays — ordered most-defining first. These are what
    /// the OC reaches for out of his signature pool and what the call sheet
    /// should badge.
    static func signaturePlays(for scheme: OffensiveScheme) -> [OffensivePlayCall] {
        offenseSignature[scheme] ?? []
    }

    /// The inverse of `installedPlays` — every scheme whose playbook contains
    /// this call. Backs `OffensivePlayCall.schemes`.
    static func schemes(installing play: OffensivePlayCall) -> [OffensiveScheme] {
        if universalOffensivePlays.contains(play) { return OffensiveScheme.allCases }
        return offenseSchemesByPlay[play] ?? []
    }

    private static let offenseInstall: [OffensiveScheme: [OffensivePlayCall]] = [

        // Rhythm quick game and yards after the catch. No true deep tab: the
        // "shot" is a boot, which is exactly the Walsh answer.
        .westCoast: [
            .insideZone, .draw, .trap,
            .screen, .slipScreen,
            .slant, .quickOut, .flat, .drag, .stick, .spot, .snag, .angle, .shallowCross,
            .curl, .levels, .sail,
            .paBoot
        ],

        // Verticals, mesh and empty sets — the ball goes down the field.
        .airRaid: [
            .draw, .qbDraw,
            .bubbleScreen, .tunnelScreen,
            .mesh, .hitch, .stick, .snag, .shallowCross,
            .dig, .dagger, .yCross, .smash,
            .fourVerts, .goRoute, .post, .sluggo
        ],

        // Space and the read game: light boxes get run on, loaded boxes get
        // thrown on, and the RPO strip decides which.
        .spread: [
            .insideZone, .wideZone, .zoneRead, .jetSweep, .qbDraw,
            .bubbleScreen, .tunnelScreen,
            .rpoBubble, .rpoSlant, .rpoStick,
            .slant, .mesh, .spot,
            .seam, .smash,
            .fourVerts, .post
        ],

        // Gap-scheme ground identity: hammer, hammer, then the shot off it.
        .powerRun: [
            .power, .duo, .trap, .counter, .dive, .insideRun, .toss, .tushPush,
            .screen,
            .stick, .flat, .fade,
            .comeback, .smash,
            .playActionDeep, .paCross
        ],

        // Outside zone married to boots and play-action crossers. The two
        // halves deliberately live in different formation families — the coach
        // cannot audible between them, he has to call them.
        .shanahan: [
            .wideZone, .insideZone, .outsideRun, .counter, .jetSweep, .endAround,
            .screen, .slipScreen,
            .flat, .drag,
            .yCross, .sail, .dagger,
            .post,
            .paBoot, .paCross, .playActionDeep
        ],

        // Dropback pro style: full-field reads, timing and the comeback.
        .proPassing: [
            .insideRun, .insideZone, .power, .draw,
            .screen,
            .hitch, .quickOut, .stick,
            .curl, .dig, .comeback, .levels, .dagger,
            .goRoute, .backShoulder, .post, .flood
        ],

        // Conflict the second level on every snap.
        .rpo: [
            .insideZone, .wideZone, .zoneRead, .qbDraw, .jetSweep,
            .rpoBubble, .rpoSlant, .rpoStick, .rpoPop,
            .bubbleScreen, .tunnelScreen,
            .slant, .drag, .spot,
            .seam, .smash,
            .post
        ],

        // Make him wrong: option, misdirection and the shot off the fake.
        .option: [
            .speedOption, .zoneRead, .insideZone, .dive, .toss, .counter,
            .endAround, .jetSweep, .tushPush,
            .bubbleScreen,
            .flat, .drag, .fade,
            .seam,
            .goRoute,
            .playActionDeep
        ]
    ]

    private static let offenseSignature: [OffensiveScheme: [OffensivePlayCall]] = [
        .westCoast:  [.spot, .angle, .shallowCross, .slipScreen],
        .airRaid:    [.fourVerts, .yCross, .sluggo, .snag],
        .spread:     [.zoneRead, .rpoBubble, .bubbleScreen, .fourVerts],
        .powerRun:   [.power, .duo, .trap, .tushPush],
        .shanahan:   [.wideZone, .paBoot, .paCross, .endAround],
        .proPassing: [.dagger, .levels, .backShoulder, .comeback],
        .rpo:        [.rpoPop, .rpoStick, .rpoSlant, .zoneRead],
        .option:     [.speedOption, .zoneRead, .endAround, .toss]
    ]

    /// Built once, in `OffensiveScheme.allCases` order so the result is stable.
    private static let offenseSchemesByPlay: [OffensivePlayCall: [OffensiveScheme]] = {
        var map: [OffensivePlayCall: [OffensiveScheme]] = [:]
        for scheme in OffensiveScheme.allCases {
            for play in offenseInstall[scheme] ?? [] {
                map[play, default: []].append(scheme)
            }
        }
        return map
    }()

    /// Whether this call is one of the scheme's identity plays.
    static func isSignature(_ play: OffensivePlayCall, of scheme: OffensiveScheme) -> Bool {
        offenseSignature[scheme]?.contains(play) ?? false
    }

    // ==================================================================
    // MARK: - Offense: call-tendency weights
    // ==================================================================

    /// The three throw depths the coordinator picks between. Mirrors
    /// `OffensivePlayCall.PassDepthHint` but is a *selection* bucket, not a
    /// simulator override.
    enum CallDepth {
        case short, medium, deep
    }

    /// The scheme's ordered run preference. Callers walk the list and take the
    /// first play the offense has actually installed.
    ///
    /// - Parameter shortYardage: true on 3rd/4th-and-short and at the goal
    ///   line, where every scheme has its own hammer.
    static func runOrder(for scheme: OffensiveScheme, shortYardage: Bool) -> [OffensivePlayCall] {
        shortYardage ? (offenseShortYardageRun[scheme] ?? []) : (offenseRunOrder[scheme] ?? [])
    }

    /// The scheme's ordered pass preference for a throw depth.
    static func passOrder(for scheme: OffensiveScheme, depth: CallDepth) -> [OffensivePlayCall] {
        switch depth {
        case .short:  return offenseShortPassOrder[scheme] ?? []
        case .medium: return offenseMediumPassOrder[scheme] ?? []
        case .deep:   return offenseDeepPassOrder[scheme] ?? []
        }
    }

    private static let offenseShortYardageRun: [OffensiveScheme: [OffensivePlayCall]] = [
        .westCoast:  [.qbSneak, .insideZone, .draw],
        .airRaid:    [.qbSneak, .qbDraw, .draw],
        .spread:     [.qbSneak, .zoneRead, .insideZone],
        .powerRun:   [.tushPush, .qbSneak, .dive, .duo],
        .shanahan:   [.qbSneak, .insideZone, .wideZone],
        .proPassing: [.qbSneak, .insideRun, .power],
        .rpo:        [.qbSneak, .zoneRead, .insideZone],
        .option:     [.tushPush, .qbSneak, .dive, .insideZone]
    ]

    private static let offenseRunOrder: [OffensiveScheme: [OffensivePlayCall]] = [
        .westCoast:  [.insideZone, .draw, .trap],
        .airRaid:    [.draw, .qbDraw],
        .spread:     [.zoneRead, .insideZone, .wideZone, .jetSweep, .qbDraw],
        .powerRun:   [.power, .duo, .insideRun, .counter, .trap, .toss],
        .shanahan:   [.wideZone, .insideZone, .counter, .outsideRun, .jetSweep, .endAround],
        .proPassing: [.insideRun, .insideZone, .power, .draw],
        .rpo:        [.insideZone, .zoneRead, .wideZone, .qbDraw, .jetSweep],
        .option:     [.speedOption, .zoneRead, .insideZone, .toss, .counter, .jetSweep, .endAround]
    ]

    private static let offenseShortPassOrder: [OffensiveScheme: [OffensivePlayCall]] = [
        .westCoast:  [.slant, .quickOut, .spot, .angle, .drag, .stick, .flat, .shallowCross],
        .airRaid:    [.mesh, .snag, .stick, .hitch, .shallowCross],
        .spread:     [.rpoBubble, .slant, .bubbleScreen, .spot, .mesh, .rpoSlant],
        .powerRun:   [.stick, .flat, .fade],
        .shanahan:   [.flat, .drag, .slipScreen],
        .proPassing: [.hitch, .quickOut, .stick],
        .rpo:        [.rpoSlant, .rpoStick, .rpoBubble, .slant, .spot, .drag],
        .option:     [.flat, .drag, .bubbleScreen, .fade]
    ]

    private static let offenseMediumPassOrder: [OffensiveScheme: [OffensivePlayCall]] = [
        .westCoast:  [.curl, .levels, .sail, .snag],
        .airRaid:    [.dig, .dagger, .yCross, .smash],
        .spread:     [.seam, .smash],
        .powerRun:   [.comeback, .smash],
        .shanahan:   [.paBoot, .yCross, .sail, .dagger],
        .proPassing: [.curl, .dig, .comeback, .levels, .dagger],
        .rpo:        [.seam, .smash, .rpoPop],
        .option:     [.seam]
    ]

    private static let offenseDeepPassOrder: [OffensiveScheme: [OffensivePlayCall]] = [
        // West Coast never gets a true deep tab — its "deep" collapses to the boot.
        .westCoast:  [.paBoot, .sail],
        .airRaid:    [.fourVerts, .post, .goRoute, .sluggo],
        .spread:     [.fourVerts, .post],
        .powerRun:   [.playActionDeep, .paCross],
        .shanahan:   [.paCross, .playActionDeep, .post],
        .proPassing: [.post, .goRoute, .backShoulder, .flood],
        .rpo:        [.post],
        .option:     [.playActionDeep, .goRoute]
    ]

    // MARK: Signature pool

    /// The share of snaps a coordinator running this scheme should spend inside
    /// his signature pool — how strongly the identity shows up on tape.
    static func signatureShare(for scheme: OffensiveScheme) -> Double {
        switch scheme {
        case .westCoast:  return 0.30
        case .airRaid:    return 0.32
        case .spread:     return 0.30
        case .powerRun:   return 0.38
        case .shanahan:   return 0.34
        case .proPassing: return 0.28
        case .rpo:        return 0.35
        case .option:     return 0.38
        }
    }

    /// The signature calls that fit THIS distance. An empty result means the
    /// scheme has no identity answer for the situation (both ground schemes go
    /// quiet in true passing downs) — the caller should fall back to its normal
    /// situational logic rather than force a signature call.
    static func signaturePool(for scheme: OffensiveScheme, distance: Int) -> [OffensivePlayCall] {
        switch scheme {
        case .westCoast:
            return distance <= 2
                ? [.slant, .quickOut, .flat, .spot]
                : [.slant, .spot, .angle, .shallowCross, .drag, .stick, .slipScreen]
        case .airRaid:
            return distance <= 2
                ? [.mesh, .snag, .stick]
                : [.fourVerts, .yCross, .dagger, .sluggo, .mesh, .post]
        case .spread:
            return distance <= 2
                ? [.rpoStick, .rpoSlant, .bubbleScreen]
                : [.zoneRead, .rpoBubble, .bubbleScreen, .fourVerts, .jetSweep]
        case .powerRun:
            if distance <= 2 { return [.tushPush, .dive, .duo, .power] }
            if distance < 8  { return [.power, .duo, .trap, .counter, .insideRun] }
            return []
        case .shanahan:
            if distance <= 2 { return [.wideZone, .insideZone] }
            if distance < 8  { return [.wideZone, .counter, .endAround, .paBoot] }
            return [.paCross, .paBoot, .yCross]
        case .proPassing:
            return distance <= 2
                ? [.hitch, .stick, .quickOut]
                : [.dagger, .levels, .dig, .comeback, .backShoulder]
        case .rpo:
            return distance <= 2
                ? [.rpoStick, .rpoPop, .zoneRead]
                : [.rpoBubble, .rpoSlant, .rpoPop, .zoneRead, .bubbleScreen]
        case .option:
            if distance <= 2 { return [.tushPush, .dive, .speedOption] }
            if distance < 8  { return [.speedOption, .zoneRead, .toss, .endAround] }
            return []
        }
    }

    // ==================================================================
    // MARK: - Defense
    // ==================================================================

    /// Calls every defense owns regardless of identity.
    static let universalDefensiveCalls: [DefensiveCall] = [
        .cover3Base, .prevent, .nickelPackage, .dimePackage, .goalLineD
    ]

    static func installedCalls(for scheme: DefensiveScheme) -> [DefensiveCall] {
        defenseInstall[scheme] ?? []
    }

    static func signatureCalls(for scheme: DefensiveScheme) -> [DefensiveCall] {
        defenseSignature[scheme] ?? []
    }

    /// Backs `DefensiveCall.schemes`.
    static func schemes(installing call: DefensiveCall) -> [DefensiveScheme] {
        if universalDefensiveCalls.contains(call) { return DefensiveScheme.allCases }
        return defenseSchemesByCall[call] ?? []
    }

    static func isSignature(_ call: DefensiveCall, of scheme: DefensiveScheme) -> Bool {
        defenseSignature[scheme]?.contains(call) ?? false
    }

    private static let defenseInstall: [DefensiveScheme: [DefensiveCall]] = [
        .base34: [
            .base34, .fireZone, .simPressure, .creeper, .edgeDog, .doubleAGap,
            .lbFire, .safetyBlitz, .cover1, .cover1Robber, .cover3Base,
            .quarters, .bearFront, .nickelPackage, .goalLineD, .prevent
        ],
        .base43: [
            .cover2Shell, .cover3Base, .cover6, .quarters, .cloud2, .cover1,
            .lbFire, .doubleAGap, .zoneBlitz, .bearFront, .nickelPackage,
            .dimePackage, .goalLineD, .prevent
        ],
        .cover3: [
            .cover3Base, .cover1, .cover1Robber, .manFree, .fireZone, .lbFire,
            .safetyBlitz, .quarters, .cover6, .nickelPackage, .bigNickel,
            .goalLineD, .prevent
        ],
        .pressMan: [
            .manPress, .manFree, .twoManUnder, .twoManPress, .cover1,
            .cover1Robber, .cover0, .allOut, .cornerBlitz, .safetyBlitz,
            .overload, .edgeDog, .dimeFire, .nickelPackage, .goalLineD, .prevent
        ],
        .tampa2: [
            .tampa2, .cover2Shell, .cover6, .cloud2, .quarters, .cover4Match,
            .zoneBlitz, .fireZone, .simPressure, .twoManUnder, .nickelPackage,
            .dimePackage, .bigNickel, .goalLineD, .prevent
        ],
        .multiple: [
            .tampa2, .cover6, .cloud2, .cover2Shell, .cover3Base, .quarters,
            .cover4Match, .cover1, .cover1Robber, .manPress, .manFree,
            .fireZone, .simPressure, .creeper, .doubleAGap, .zoneBlitz,
            .safetyBlitz, .cornerBlitz, .allOut, .base34, .bearFront,
            .bigNickel, .nickelPackage, .dimePackage, .goalLineD, .prevent
        ],
        .hybrid: [
            .cover1Robber, .cover1, .cover6, .cloud2, .quarters, .cover4Match,
            .manPress, .manFree, .twoManUnder, .twoManPress, .creeper,
            .simPressure, .fireZone, .zoneBlitz, .safetyBlitz, .cornerBlitz,
            .edgeDog, .bigNickel, .base34, .nickelPackage, .dimePackage,
            .goalLineD, .prevent
        ]
    ]

    private static let defenseSignature: [DefensiveScheme: [DefensiveCall]] = [
        .base34:   [.base34, .fireZone, .creeper, .edgeDog],
        .base43:   [.cover2Shell, .bearFront, .lbFire, .cloud2],
        // "Press bail" is Cover 3 out of nickel, not a separate call.
        .cover3:   [.fireZone, .cover1Robber, .cover3Base],
        .pressMan: [.cover0, .overload, .manPress, .cornerBlitz],
        .tampa2:   [.tampa2, .cloud2, .cover6, .simPressure],
        .multiple: [.simPressure, .creeper, .cover6, .bearFront],
        .hybrid:   [.cover1Robber, .bigNickel, .creeper, .cover6]
    ]

    private static let defenseSchemesByCall: [DefensiveCall: [DefensiveScheme]] = {
        var map: [DefensiveCall: [DefensiveScheme]] = [:]
        for scheme in DefensiveScheme.allCases {
            for call in defenseInstall[scheme] ?? [] {
                map[call, default: []].append(scheme)
            }
        }
        return map
    }()

    // MARK: Defensive mix

    /// The shell/pressure mix a scheme's base logic should trend toward. Shares
    /// are independent rates, not a partition — `manShare` is the fraction of
    /// snaps in man coverage, `blitzShare` the fraction sending five or more,
    /// `twoHighShare` the fraction showing two deep safeties.
    struct DefensiveMix: Equatable {
        var manShare: Double
        var blitzShare: Double
        var twoHighShare: Double
    }

    static func mix(for scheme: DefensiveScheme) -> DefensiveMix {
        switch scheme {
        case .base34:   return DefensiveMix(manShare: 0.30, blitzShare: 0.42, twoHighShare: 0.25)
        case .base43:   return DefensiveMix(manShare: 0.18, blitzShare: 0.28, twoHighShare: 0.45)
        case .cover3:   return DefensiveMix(manShare: 0.28, blitzShare: 0.30, twoHighShare: 0.22)
        case .pressMan: return DefensiveMix(manShare: 0.72, blitzShare: 0.48, twoHighShare: 0.20)
        case .tampa2:   return DefensiveMix(manShare: 0.15, blitzShare: 0.22, twoHighShare: 0.62)
        case .multiple: return DefensiveMix(manShare: 0.35, blitzShare: 0.40, twoHighShare: 0.40)
        case .hybrid:   return DefensiveMix(manShare: 0.45, blitzShare: 0.35, twoHighShare: 0.38)
        }
    }

    /// The exotic pressure calls this scheme adds to the shared exotic pool
    /// (`[.doubleAGap, .zoneBlitz, .bearFront]`). Scheme-specific heat the DC
    /// only reaches for in long-yardage situations.
    static func exoticAdditions(for scheme: DefensiveScheme) -> [DefensiveCall] {
        switch scheme {
        case .base34:   return [.fireZone, .creeper]
        case .base43:   return [.bearFront, .doubleAGap]
        case .cover3:   return [.fireZone]
        case .pressMan: return [.cover0, .overload]
        case .tampa2:   return [.simPressure, .zoneBlitz]
        case .multiple: return [.simPressure, .creeper, .cover0]
        case .hybrid:   return [.creeper, .cover1Robber]
        }
    }

    // ==================================================================
    // MARK: - Catalog audit (DEBUG)
    // ==================================================================

    #if DEBUG
    /// Structural invariants over the 65-play / 33-call catalog. Returns a list
    /// of human-readable problems; empty means the catalog is coherent.
    ///
    /// Catches exactly the mistakes a hand-maintained catalog invites: a new
    /// case forgotten in `isRun`/`isPass`, a play whose declared category does
    /// not match how the simulator will actually resolve it, or a scheme whose
    /// ordered preference list names a play it never installed (which would
    /// make the AI silently fall through to its category default forever).
    static func catalogAudit() -> [String] {
        var problems: [String] = []

        for play in OffensivePlayCall.allCases {
            let flags = [play.isRun, play.isPass, play.isSpecial].filter { $0 }.count
            if flags != 1 {
                problems.append("\(play.rawValue): expected exactly one of isRun/isPass/isSpecial, got \(flags)")
            }
            // A screen is categorised as a screen but resolves as a pass; the
            // clock plays resolve as themselves. Everything else must agree.
            let resolved = PlaySimulator.playType(for: play)
            switch play.category {
            case "Run":
                if resolved != .run { problems.append("\(play.rawValue): Run tab but resolves as \(resolved)") }
            case "Screen", "Short Pass", "Medium Pass", "Deep Pass", "Play Action", "RPO":
                if resolved != .pass { problems.append("\(play.rawValue): pass tab but resolves as \(resolved)") }
            default:
                break
            }
        }

        for scheme in OffensiveScheme.allCases {
            let installed = Set(installedPlays(for: scheme) + universalOffensivePlays)
            var ordered = runOrder(for: scheme, shortYardage: true)
                + runOrder(for: scheme, shortYardage: false)
                + signaturePlays(for: scheme)
            for depth: CallDepth in [.short, .medium, .deep] {
                ordered += passOrder(for: scheme, depth: depth)
            }
            for distance in [1, 5, 12] { ordered += signaturePool(for: scheme, distance: distance) }
            for play in Set(ordered) where !installed.contains(play) {
                problems.append("\(scheme.rawValue): preference list names \(play.rawValue), which it does not install")
            }
        }

        // Signatures only. `exoticAdditions` is deliberately allowed to name a
        // call the scheme does not install — an exotic is a long-yardage
        // gamble, and `LiveGameEngine.installedDefensiveEquivalent` already
        // walks it back to an installed call of the same intent.
        for scheme in DefensiveScheme.allCases {
            let installed = Set(installedCalls(for: scheme) + universalDefensiveCalls)
            for call in signatureCalls(for: scheme) where !installed.contains(call) {
                problems.append("\(scheme.rawValue): signature \(call.rawValue) is not installed")
            }
        }

        return problems
    }
    #endif
}
