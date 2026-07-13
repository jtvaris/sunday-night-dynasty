import Foundation

// MARK: - Offensive Play Call

/// A specific offensive play the player can call from the play-call UI.
///
/// Calls are grouped into five logical categories that map directly to the
/// `PlayCallView` grid sections.  Each case also exposes convenience flags
/// (`isRun` / `isPass`) so `PlaySimulator` can route the call to the correct
/// simulation path, and a `simulatorHint` that carries lightweight modifiers
/// the simulator uses to shade probabilities (depth, aggressiveness, etc.).
enum OffensivePlayCall: String, Codable, CaseIterable {

    // Run
    case insideRun   = "Inside Run"
    case outsideRun  = "Outside Run"
    case counter     = "Counter"
    case toss        = "Toss Sweep"
    case draw        = "Draw"
    case screen      = "Screen"
    case dive        = "Goal Line Dive"
    case jetSweep    = "Jet Sweep"

    // Short Pass (0-10 yards)
    case slant       = "Slant"
    case quickOut    = "Quick Out"
    case hitch       = "Hitch"
    case flat        = "Flat"
    case drag        = "Drag"
    case stick       = "Stick"
    case mesh        = "Mesh"

    // Medium Pass (11-20 yards)
    case curl        = "Curl"
    case dig         = "Dig"
    case seam        = "TE Seam"
    case cross       = "Deep Cross"
    case postCorner  = "Post Corner"
    case comeback    = "Comeback"
    case wheel       = "Wheel"

    // Deep Pass (21+ yards)
    case goRoute     = "Go Route"
    case post        = "Post"
    case corner      = "Corner"
    case flood       = "Flood"
    case bomb        = "Bomb"
    case playActionDeep = "Play Action Deep"

    // Special
    case qbSneak     = "QB Sneak"
    case spike       = "Spike"
    case kneel       = "Kneel"

    // MARK: Category

    /// The display category label shown in `PlayCallView`.
    var category: String {
        switch self {
        case .insideRun, .outsideRun, .counter, .toss, .draw, .screen, .dive, .jetSweep:
            return "Run"
        case .slant, .quickOut, .hitch, .flat, .drag, .stick, .mesh:
            return "Short Pass"
        case .curl, .dig, .seam, .cross, .postCorner, .comeback, .wheel:
            return "Medium Pass"
        case .goRoute, .post, .corner, .flood, .bomb, .playActionDeep:
            return "Deep Pass"
        case .qbSneak, .spike, .kneel:
            return "Special"
        }
    }

    /// One-line coach-speak description shown under the play card.
    var blurb: String {
        switch self {
        case .insideRun:  return "Downhill between the tackles."
        case .outsideRun: return "Stretch the edge, cut upfield."
        case .counter:    return "Misdirection — guard pulls, back cuts back."
        case .toss:       return "Pitch wide and win with speed."
        case .draw:       return "Sell the pass, delayed handoff inside."
        case .screen:     return "Invite the rush, dump it to the back."
        case .dive:       return "Hammer the middle for the tough yard."
        case .jetSweep:   return "Motion man takes it at full speed."
        case .slant:      return "Quick in-cut behind the blitz."
        case .quickOut:   return "Three-step timing to the sideline."
        case .hitch:      return "Catch and turn at five yards."
        case .flat:       return "Safety valve to the back in the flat."
        case .drag:       return "Shallow cross under the coverage."
        case .stick:      return "TE settles at the sticks, outlet ready."
        case .mesh:       return "Two crossers rub free underneath."
        case .curl:       return "Break back to the ball at twelve."
        case .dig:        return "Square-in behind the linebackers."
        case .seam:       return "Tight end splits the safeties."
        case .cross:      return "Deep crosser beats man coverage."
        case .postCorner: return "Double move, break to the pylon."
        case .comeback:   return "Sell vertical, snap back to the boundary."
        case .wheel:      return "Back leaks out and turns up the sideline."
        case .goRoute:    return "Straight vertical — take the top off."
        case .post:       return "Break inside behind the safety."
        case .corner:     return "Angle to the flag, away from help."
        case .flood:      return "Three levels flood one sideline."
        case .bomb:       return "Max protect and let it fly."
        case .playActionDeep: return "Fake the run, launch it over the top."
        case .qbSneak:    return "Surge behind center for the yard."
        case .spike:      return "Kill the clock."
        case .kneel:      return "Victory formation."
        }
    }

    // MARK: Type Flags

    var isRun: Bool {
        switch self {
        case .insideRun, .outsideRun, .counter, .toss, .draw, .screen,
             .dive, .jetSweep, .qbSneak:
            return true
        default: return false
        }
    }

    var isPass: Bool {
        switch self {
        case .slant, .quickOut, .hitch, .flat, .drag, .stick, .mesh,
             .curl, .dig, .seam, .cross, .postCorner, .comeback, .wheel,
             .goRoute, .post, .corner, .flood, .bomb, .playActionDeep:
            return true
        default: return false
        }
    }

    var isSpecial: Bool {
        switch self {
        case .spike, .kneel: return true
        default: return false
        }
    }

    // MARK: Playbook Membership

    /// The offensive schemes whose playbook installs this play. A team's
    /// call sheet highlights plays from its coordinator's scheme; calling
    /// outside the installed playbook raises the busted-assignment risk
    /// (see `MatchupResolver.bustRoll`).
    var schemes: [OffensiveScheme] {
        switch self {
        case .insideRun:  return [.powerRun, .shanahan, .rpo, .option, .proPassing, .spread]
        case .outsideRun: return [.shanahan, .option, .spread, .powerRun, .rpo]
        case .counter:    return [.powerRun, .shanahan, .option, .proPassing]
        case .toss:       return [.powerRun, .option, .shanahan, .spread]
        case .draw:       return [.powerRun, .proPassing, .spread, .rpo]
        case .screen:     return [.westCoast, .airRaid, .shanahan, .proPassing, .spread]
        case .dive:       return [.powerRun, .option, .shanahan, .proPassing]
        case .jetSweep:   return [.spread, .rpo, .option, .shanahan]
        case .slant:      return [.westCoast, .spread, .rpo, .proPassing, .airRaid]
        case .quickOut:   return [.westCoast, .airRaid, .rpo, .spread]
        case .hitch:      return [.westCoast, .airRaid, .proPassing, .rpo, .spread]
        case .flat:       return [.westCoast, .shanahan, .powerRun, .option]
        case .drag:       return [.westCoast, .spread, .rpo, .shanahan, .option]
        case .stick:      return [.westCoast, .airRaid, .proPassing, .spread]
        case .mesh:       return [.airRaid, .spread, .rpo, .westCoast]
        case .curl:       return [.westCoast, .proPassing, .airRaid]
        case .dig:        return [.airRaid, .proPassing, .spread, .westCoast, .shanahan]
        case .seam:       return [.airRaid, .spread, .rpo, .westCoast, .proPassing]
        case .cross:      return [.shanahan, .westCoast, .airRaid, .proPassing]
        case .postCorner: return [.airRaid, .proPassing, .powerRun]
        case .comeback:   return [.proPassing, .westCoast, .powerRun]
        case .wheel:      return [.shanahan, .westCoast, .proPassing, .airRaid]
        case .goRoute:    return [.airRaid, .spread, .proPassing, .option]
        case .post:       return [.airRaid, .proPassing, .spread, .rpo, .shanahan]
        case .corner:     return [.airRaid, .shanahan, .proPassing]
        case .flood:      return [.shanahan, .airRaid, .proPassing, .westCoast]
        case .bomb:       return [.airRaid, .spread]
        case .playActionDeep: return [.shanahan, .powerRun, .proPassing, .rpo]
        case .qbSneak, .spike, .kneel: return OffensiveScheme.allCases
        }
    }

    /// Whether this play is part of the given scheme's installed playbook.
    func isInPlaybook(of scheme: OffensiveScheme?) -> Bool {
        guard let scheme else { return true }
        return schemes.contains(scheme)
    }

    // MARK: Formation Family (R36 audibles)

    /// Pre-snap alignment families, mirroring the call-driven alignment
    /// switch in `PlayChoreographer.offensePositions` exactly. An audible can
    /// only check into a play from the SAME family — the offense is already
    /// lined up in that look, so the swap needs no re-alignment.
    enum FormationFamily: String {
        case iForm       // QB under center, back deep downhill
        case stretch     // sprint flow to the edge
        case backfield   // deep gun set, back beside the QB
        case quick       // wide splits, three-step timing
        case crossSet    // slot flipped right for the crossers
        case spreadDeep  // maximum width, everyone vertical
        case baseGun     // the standard shotgun look
        case special     // spike/kneel — never audibled into or out of
    }

    /// The alignment family this call snaps from (see `FormationFamily`).
    var formationFamily: FormationFamily {
        switch self {
        case .insideRun, .qbSneak, .dive:                       return .iForm
        case .outsideRun, .jetSweep:                            return .stretch
        case .draw, .screen:                                    return .backfield
        case .slant, .quickOut, .flat, .drag, .stick, .mesh:    return .quick
        case .cross:                                            return .crossSet
        case .goRoute, .post, .corner, .bomb, .playActionDeep:  return .spreadDeep
        case .spike, .kneel:                                    return .special
        default:                                                return .baseGun
        }
    }

    /// The plays this call can audible into: same formation family, installed
    /// per the caller's check, never itself and never a special. Order is the
    /// declaration order of the call sheet.
    func audibleOptions(installed: (OffensivePlayCall) -> Bool) -> [OffensivePlayCall] {
        guard formationFamily != .special else { return [] }
        return OffensivePlayCall.allCases.filter {
            $0 != self && $0.formationFamily == formationFamily && installed($0)
        }
    }

    /// Whether this play historically fares well against the given coverage
    /// shell — the ✓ tag on the audible strip. Pure pre-snap information for
    /// the coach (fed by the QB's coverage read); the sim never reads it.
    func goodAgainst(_ coverage: DefensivePlayCall) -> Bool {
        switch coverage {
        case .manToMan:
            // Rubs and crossers shake man coverage.
            return [.drag, .mesh, .cross, .slant, .wheel, .jetSweep].contains(self)
        case .cover1:
            // Attack the lone deep safety.
            return [.post, .goRoute, .bomb, .playActionDeep, .cross].contains(self)
        case .cover2:
            // The seams and the deep middle split a two-high shell.
            return [.seam, .post, .dig, .corner, .cross].contains(self)
        case .cover3:
            // Out-breaking timing throws beat the three-deep zone.
            return [.quickOut, .flat, .comeback, .curl, .stick].contains(self)
        case .cover4:
            // Quarters gives the ground game and the flats away.
            return [.insideRun, .outsideRun, .counter, .toss, .flat, .drag].contains(self)
        case .prevent:
            // Take the free underneath yards.
            return [.slant, .hitch, .drag, .screen, .draw, .insideRun].contains(self)
        default:
            return false
        }
    }

    // MARK: Simulator Hint

    /// A lightweight struct the `PlaySimulator` reads to adjust probabilities.
    ///
    /// - `passDepth`: Overrides the automatic depth selection.  `nil` means
    ///   the simulator chooses depth normally.
    /// - `runGapBonus`: Additive bonus (0.0–1.0) applied to run-blocking
    ///   advantage.  Positive = interior power run; negative = stretch/outside.
    /// - `blitzPickupBonus`: Extra pass-protection credit for quick-timing
    ///   throws (slants, flats) that neutralise blitz pressure.
    /// - `yacMultiplier`: Multiplier on yards-after-catch for plays that
    ///   rely on open-field running (screens, go routes).
    struct SimulatorHint {
        var passDepth: PassDepthHint?
        var runGapBonus: Double
        var blitzPickupBonus: Double
        var yacMultiplier: Double
        /// True for run-fake passes: the sim rolls whether the box bites on
        /// the fake (awareness-driven, R37) and shades the completion odds.
        var isPlayAction: Bool = false

        static let neutral = SimulatorHint(
            passDepth: nil,
            runGapBonus: 0,
            blitzPickupBonus: 0,
            yacMultiplier: 1.0
        )
    }

    enum PassDepthHint: String {
        case short
        case medium
        case deep
    }

    var simulatorHint: SimulatorHint {
        switch self {
        // --- Run plays ---
        case .insideRun:
            return SimulatorHint(passDepth: nil, runGapBonus: 0.15, blitzPickupBonus: 0, yacMultiplier: 1.0)
        case .outsideRun:
            return SimulatorHint(passDepth: nil, runGapBonus: -0.05, blitzPickupBonus: 0, yacMultiplier: 1.3)
        case .counter:
            // Misdirection: interior gap credit once the pursuit over-flows
            return SimulatorHint(passDepth: nil, runGapBonus: 0.1, blitzPickupBonus: 0, yacMultiplier: 1.15)
        case .toss:
            // Edge speed: boom-or-bust to the perimeter
            return SimulatorHint(passDepth: nil, runGapBonus: -0.1, blitzPickupBonus: 0, yacMultiplier: 1.45)
        case .draw:
            // Draw holds the pass rush briefly; slightly better vs. blitz
            return SimulatorHint(passDepth: nil, runGapBonus: 0.05, blitzPickupBonus: 0.1, yacMultiplier: 1.1)
        case .screen:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.2, yacMultiplier: 1.8)
        case .dive:
            // Short-yardage hammer: maximum interior push, minimal breakaway.
            return SimulatorHint(passDepth: nil, runGapBonus: 0.28, blitzPickupBonus: 0, yacMultiplier: 0.7)
        case .jetSweep:
            // Full-speed handoff at the edge: boom-or-bust with big YAC.
            return SimulatorHint(passDepth: nil, runGapBonus: -0.15, blitzPickupBonus: 0.05, yacMultiplier: 1.6)

        // --- Short pass ---
        case .slant:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.15, yacMultiplier: 1.2)
        case .quickOut:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.2, yacMultiplier: 0.8)
        case .hitch:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.2, yacMultiplier: 0.9)
        case .flat:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.25, yacMultiplier: 1.5)
        case .drag:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.1, yacMultiplier: 1.1)
        case .stick:
            // Quick-game staple: the ball is out before the pressure arrives.
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.25, yacMultiplier: 0.85)
        case .mesh:
            // Crossers rub free — catch on the move with room to run.
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.1, yacMultiplier: 1.35)

        // --- Medium pass ---
        case .curl:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0, yacMultiplier: 0.9)
        case .dig:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.05, yacMultiplier: 1.0)
        case .seam:
            // TE up the middle: big YAC when the safeties split
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.05, yacMultiplier: 1.3)
        case .cross:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.05, yacMultiplier: 1.25)
        case .postCorner:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.1, yacMultiplier: 1.1)
        case .comeback:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0, yacMultiplier: 0.8)
        case .wheel:
            // Back sneaks out on a linebacker — open grass when it hits.
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0.05, yacMultiplier: 1.4)

        // --- Deep pass ---
        case .goRoute:
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.15, yacMultiplier: 1.0)
        case .post:
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.1, yacMultiplier: 1.2)
        case .corner:
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.1, yacMultiplier: 0.9)
        case .flood:
            // Three levels one side: an easier read with a checkdown built in
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: 0.05, yacMultiplier: 1.1)
        case .bomb:
            // Maximum depth; higher INT risk, massive upside
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.2, yacMultiplier: 1.0)
        case .playActionDeep:
            // The fake holds the second level; the long drop invites the rush.
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.15,
                                 yacMultiplier: 1.15, isPlayAction: true)

        // --- Special ---
        case .qbSneak:
            return SimulatorHint(passDepth: nil, runGapBonus: 0.3, blitzPickupBonus: 0, yacMultiplier: 1.0)
        case .spike, .kneel:
            return SimulatorHint(passDepth: nil, runGapBonus: 0, blitzPickupBonus: 0, yacMultiplier: 1.0)
        }
    }
}

// MARK: - Defensive Play Call

/// A defensive call the player can make against the offense.
///
/// Calls span three adjustable dimensions — coverage shell, blitz package, and
/// defensive front — so the player can mix and match them independently.  The
/// display in `PlayCallView` groups these into three columns; only one value
/// from each group is active at a time.
enum DefensivePlayCall: String, Codable, CaseIterable {

    // Coverage shell
    case cover1     = "Cover 1"
    case cover2     = "Cover 2"
    case cover3     = "Cover 3"
    case cover4     = "Cover 4"
    case manToMan   = "Man Coverage"
    case prevent    = "Prevent"

    // Blitz package
    case noBlitz    = "No Blitz"
    case lbBlitz    = "LB Blitz"
    case doubleAGap = "Double A-Gap"
    case safetyBlitz = "Safety Blitz"
    case dbBlitz    = "DB Blitz"
    case allOutBlitz = "All-Out Blitz"

    // Defensive front
    case base       = "Base 4-3"
    case nickel     = "Nickel"
    case dime       = "Dime"
    case bear       = "Bear Front"
    case goalLine   = "Goal Line"

    // MARK: Category

    var category: String {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .manToMan, .prevent:
            return "Coverage"
        case .noBlitz, .lbBlitz, .doubleAGap, .safetyBlitz, .dbBlitz, .allOutBlitz:
            return "Blitz"
        case .base, .nickel, .dime, .bear, .goalLine:
            return "Front"
        }
    }

    // MARK: Simulator Modifiers

    /// How much this call adjusts the coverage quality seen by the offense.
    /// Positive values tighten coverage (reduces completion %).
    var coverageModifier: Double {
        switch self {
        case .cover1:     return 0.10    // man free: tight with a single-high net
        case .cover2:     return 0.05
        case .cover3:     return 0.08
        case .cover4:     return 0.10
        case .manToMan:   return 0.12    // tightest, but vulnerable to big plays
        case .prevent:    return 0.04    // soft overall; the depth shading does the work
        case .noBlitz:    return 0.02
        case .lbBlitz:    return 0.0
        case .doubleAGap: return -0.06   // both backers vacate the middle
        case .safetyBlitz:return -0.06   // the deep net loses a defender
        case .dbBlitz:    return -0.04   // DB in blitz = less coverage help
        case .allOutBlitz:return -0.10
        case .base:       return 0.02
        case .nickel:     return 0.05
        case .dime:       return 0.08
        case .bear:       return -0.04   // heavy box, light secondary help
        case .goalLine:   return -0.05   // heavy front, weaker pass coverage
        }
    }

    /// How much this call adds to the pass-rush pressure on the QB.
    /// Feeds into sack-chance and blitz-pickup calculations.
    var pressureModifier: Double {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .manToMan: return 0.0
        case .prevent:    return -0.02   // rush three, everyone else drops
        case .noBlitz:    return 0.0
        case .lbBlitz:    return 0.06
        case .doubleAGap: return 0.10    // interior heat right up the middle
        case .safetyBlitz:return 0.08
        case .dbBlitz:    return 0.04
        case .allOutBlitz:return 0.12
        case .base:       return 0.02
        case .nickel:     return -0.02   // fewer DL
        case .dime:       return -0.04
        case .bear:       return 0.05    // extra bodies crowd the line
        case .goalLine:   return 0.06
        }
    }

    /// How much this call improves run stopping.
    var runStopModifier: Double {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .manToMan: return 0.0
        case .prevent:    return -0.06   // soft shell concedes the ground game
        case .noBlitz, .lbBlitz, .dbBlitz, .allOutBlitz: return 0.0
        case .doubleAGap: return 0.04    // mugged-up backers plug the middle
        case .safetyBlitz:return 0.02
        case .base:       return 0.08
        case .nickel:     return -0.05
        case .dime:       return -0.10
        case .bear:       return 0.14    // 46-style front swallows interior runs
        case .goalLine:   return 0.18
        }
    }

    // MARK: Shell Audibles (R36)

    /// The coverage shells a defensive audible can rotate into at the line
    /// (prevent stays a situational call — never an audible target).
    static let audibleShells: [DefensivePlayCall] = [
        .cover1, .cover2, .cover3, .cover4, .manToMan
    ]

    /// Short chip label for the shell-audible strip.
    var shellShortLabel: String {
        switch self {
        case .manToMan: return "Man"
        case .cover4:   return "Quarters"
        default:        return rawValue
        }
    }

    // MARK: Depth-Shaded Coverage (live games only)

    /// Extra completion penalty applied ONLY to deep throws. The prevent
    /// shell takes away the bomb while conceding the underneath game.
    var deepCoverageModifier: Double {
        switch self {
        case .prevent: return 0.14
        case .cover1:  return 0.03   // the free safety caps verticals
        default:       return 0
        }
    }

    /// Extra completion penalty applied ONLY to short throws — negative
    /// values make the checkdown easier (prevent gives the underneath away).
    var shortCoverageModifier: Double {
        switch self {
        case .prevent: return -0.08
        default:       return 0
        }
    }
}

// MARK: - Combined Defensive Package

/// Bundles the three independent defensive dimensions into a single value that
/// `PlayCallView` produces and `PlaySimulator` consumes.
struct DefensivePackage: Equatable {
    var coverage: DefensivePlayCall
    var blitz:    DefensivePlayCall
    var front:    DefensivePlayCall

    // MARK: Defaults

    static let standard = DefensivePackage(
        coverage: .cover3,
        blitz: .noBlitz,
        front: .base
    )

    // MARK: Aggregate Modifiers (sum all three dimensions)

    var totalCoverageModifier: Double {
        coverage.coverageModifier + blitz.coverageModifier + front.coverageModifier
    }

    var totalPressureModifier: Double {
        coverage.pressureModifier + blitz.pressureModifier + front.pressureModifier
    }

    var totalRunStopModifier: Double {
        coverage.runStopModifier + blitz.runStopModifier + front.runStopModifier
    }

    /// Depth-shaded coverage (deep throws only). Live games only — the quick
    /// sim passes a nil package and never sees these.
    var totalDeepCoverageModifier: Double {
        coverage.deepCoverageModifier + blitz.deepCoverageModifier + front.deepCoverageModifier
    }

    /// Depth-shaded coverage (short throws only).
    var totalShortCoverageModifier: Double {
        coverage.shortCoverageModifier + blitz.shortCoverageModifier + front.shortCoverageModifier
    }
}

// MARK: - Control Mode

/// Determines which sides of the ball the player actively calls plays for.
enum MatchControlMode: String, CaseIterable {
    case autoSimulate  = "Auto"
    case callOffense   = "Offense"
    case callDefense   = "Defense"
    case callBoth      = "Both"

    var playerCallsOffense: Bool { self == .callOffense || self == .callBoth }
    var playerCallsDefense: Bool { self == .callDefense || self == .callBoth }

    var icon: String {
        switch self {
        case .autoSimulate: return "play.circle"
        case .callOffense:  return "arrow.right.circle"
        case .callDefense:  return "shield.lefthalf.filled"
        case .callBoth:     return "person.fill.checkmark"
        }
    }

    var label: String { rawValue }
}

// MARK: - Named Defensive Calls

/// The defensive call sheet: named, coach-speak defensive plays the user picks
/// from during a live game. Each call bundles a coverage/blitz/front package
/// and is tagged with the defensive schemes whose playbook installs it.
///
/// Calls are grouped into four clipboard categories — Coverage, Pressure,
/// Man, Packages — mirroring the offensive call sheet's category tabs.
enum DefensiveCall: String, CaseIterable, Identifiable {

    // Coverage (zone shells)
    case cover1      = "Cover 1"
    case cover2Shell = "Cover 2 Shell"
    case cover3Base  = "Cover 3"
    case quarters    = "Quarters"
    case cover4Match = "Cover 4 Match"
    case prevent     = "Prevent"

    // Pressure (blitzes)
    case lbFire      = "LB Blitz"
    case doubleAGap  = "Double A-Gap"
    case zoneBlitz   = "Zone Blitz"
    case safetyBlitz = "Safety Blitz"
    case cornerBlitz = "Corner Blitz"
    case allOut      = "All-Out Blitz"

    // Man (man-to-man shells)
    case manPress    = "Man Press"
    case manFree     = "Man Free"
    case twoManUnder = "2-Man Under"

    // Packages (personnel groupings)
    case nickelPackage = "Nickel"
    case dimePackage   = "Dime"
    case goalLineD     = "Goal Line"
    case bearFront     = "Bear Front"

    var id: String { rawValue }

    /// The clipboard category tab this call lives under.
    var category: String {
        switch self {
        case .cover1, .cover2Shell, .cover3Base, .quarters, .cover4Match, .prevent:
            return "Coverage"
        case .lbFire, .doubleAGap, .zoneBlitz, .safetyBlitz, .cornerBlitz, .allOut:
            return "Pressure"
        case .manPress, .manFree, .twoManUnder:
            return "Man"
        case .nickelPackage, .dimePackage, .goalLineD, .bearFront:
            return "Packages"
        }
    }

    var package: DefensivePackage {
        switch self {
        case .cover1:      return DefensivePackage(coverage: .cover1, blitz: .noBlitz, front: .base)
        case .cover2Shell: return DefensivePackage(coverage: .cover2, blitz: .noBlitz, front: .base)
        case .cover3Base:  return DefensivePackage(coverage: .cover3, blitz: .noBlitz, front: .base)
        case .quarters:    return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .nickel)
        case .cover4Match: return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .base)
        case .prevent:     return DefensivePackage(coverage: .prevent, blitz: .noBlitz, front: .dime)
        case .lbFire:      return DefensivePackage(coverage: .cover3, blitz: .lbBlitz, front: .base)
        case .doubleAGap:  return DefensivePackage(coverage: .cover1, blitz: .doubleAGap, front: .base)
        case .zoneBlitz:   return DefensivePackage(coverage: .cover2, blitz: .lbBlitz, front: .nickel)
        case .safetyBlitz: return DefensivePackage(coverage: .cover1, blitz: .safetyBlitz, front: .base)
        case .cornerBlitz: return DefensivePackage(coverage: .manToMan, blitz: .dbBlitz, front: .nickel)
        case .allOut:      return DefensivePackage(coverage: .manToMan, blitz: .allOutBlitz, front: .nickel)
        case .manPress:    return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .nickel)
        case .manFree:     return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .base)
        case .twoManUnder: return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .dime)
        case .nickelPackage: return DefensivePackage(coverage: .cover3, blitz: .noBlitz, front: .nickel)
        case .dimePackage:   return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .dime)
        case .goalLineD:     return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        case .bearFront:     return DefensivePackage(coverage: .cover1, blitz: .noBlitz, front: .bear)
        }
    }

    /// One-line description shown under the call card.
    var blurb: String {
        switch self {
        case .cover1:      return "One high safety, man underneath everywhere."
        case .cover2Shell: return "Two-high shell, corners squat on the flats."
        case .cover3Base:  return "Three deep, four under — sound vs everything."
        case .quarters:    return "Four deep. Nothing gets over the top."
        case .cover4Match: return "Quarters that lock on when routes declare."
        case .prevent:     return "Concede underneath, never the bomb."
        case .lbFire:      return "Fire a backer through the A-gap."
        case .doubleAGap:  return "Both backers mug the center — instant heat."
        case .zoneBlitz:   return "Backer comes, coverage rotates behind it."
        case .safetyBlitz: return "Safety times the snap off the edge."
        case .cornerBlitz: return "Nickel screams in off the edge."
        case .allOut:      return "Everybody comes. Win the down right now."
        case .manPress:    return "Corners in their face — no free releases."
        case .manFree:     return "Tight man with a free safety cleaning up."
        case .twoManUnder: return "Two deep, man under — nothing cheap."
        case .nickelPackage: return "Fifth DB in — built for the passing down."
        case .dimePackage:   return "Six DBs blanket every route underneath."
        case .goalLineD:     return "Big bodies, zero cushion — stack the line."
        case .bearFront:     return "46 look: eight in the box, run stops here."
        }
    }

    /// The defensive schemes whose playbook installs this call.
    var schemes: [DefensiveScheme] {
        switch self {
        case .cover1:      return [.pressMan, .cover3, .hybrid, .multiple, .base34]
        case .cover2Shell: return [.tampa2, .base43, .multiple, .hybrid]
        case .cover3Base:  return DefensiveScheme.allCases
        case .quarters:    return [.tampa2, .multiple, .hybrid, .cover3]
        case .cover4Match: return [.tampa2, .hybrid, .multiple]
        case .prevent:     return DefensiveScheme.allCases
        case .lbFire:      return [.base34, .base43, .multiple, .cover3]
        case .doubleAGap:  return [.base34, .base43, .multiple]
        case .zoneBlitz:   return [.base34, .tampa2, .hybrid, .multiple]
        case .safetyBlitz: return [.base34, .pressMan, .multiple, .hybrid]
        case .cornerBlitz: return [.pressMan, .multiple, .hybrid]
        case .allOut:      return [.pressMan, .multiple, .base34]
        case .manPress:    return [.pressMan, .hybrid, .multiple]
        case .manFree:     return [.pressMan, .cover3, .hybrid, .multiple]
        case .twoManUnder: return [.pressMan, .tampa2, .multiple, .hybrid]
        case .nickelPackage: return DefensiveScheme.allCases
        case .dimePackage:   return DefensiveScheme.allCases
        case .goalLineD:     return DefensiveScheme.allCases
        case .bearFront:     return [.base34, .base43, .multiple]
        }
    }

    func isInPlaybook(of scheme: DefensiveScheme?) -> Bool {
        guard let scheme else { return true }
        return schemes.contains(scheme)
    }
}
