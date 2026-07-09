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

    // Short Pass (0-10 yards)
    case slant       = "Slant"
    case quickOut    = "Quick Out"
    case hitch       = "Hitch"
    case flat        = "Flat"
    case drag        = "Drag"

    // Medium Pass (11-20 yards)
    case curl        = "Curl"
    case dig         = "Dig"
    case seam        = "TE Seam"
    case cross       = "Deep Cross"
    case postCorner  = "Post Corner"
    case comeback    = "Comeback"

    // Deep Pass (21+ yards)
    case goRoute     = "Go Route"
    case post        = "Post"
    case corner      = "Corner"
    case flood       = "Flood"
    case bomb        = "Bomb"

    // Special
    case qbSneak     = "QB Sneak"
    case spike       = "Spike"
    case kneel       = "Kneel"

    // MARK: Category

    /// The display category label shown in `PlayCallView`.
    var category: String {
        switch self {
        case .insideRun, .outsideRun, .counter, .toss, .draw, .screen:
            return "Run"
        case .slant, .quickOut, .hitch, .flat, .drag:
            return "Short Pass"
        case .curl, .dig, .seam, .cross, .postCorner, .comeback:
            return "Medium Pass"
        case .goRoute, .post, .corner, .flood, .bomb:
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
        case .slant:      return "Quick in-cut behind the blitz."
        case .quickOut:   return "Three-step timing to the sideline."
        case .hitch:      return "Catch and turn at five yards."
        case .flat:       return "Safety valve to the back in the flat."
        case .drag:       return "Shallow cross under the coverage."
        case .curl:       return "Break back to the ball at twelve."
        case .dig:        return "Square-in behind the linebackers."
        case .seam:       return "Tight end splits the safeties."
        case .cross:      return "Deep crosser beats man coverage."
        case .postCorner: return "Double move, break to the pylon."
        case .comeback:   return "Sell vertical, snap back to the boundary."
        case .goRoute:    return "Straight vertical — take the top off."
        case .post:       return "Break inside behind the safety."
        case .corner:     return "Angle to the flag, away from help."
        case .flood:      return "Three levels flood one sideline."
        case .bomb:       return "Max protect and let it fly."
        case .qbSneak:    return "Surge behind center for the yard."
        case .spike:      return "Kill the clock."
        case .kneel:      return "Victory formation."
        }
    }

    // MARK: Type Flags

    var isRun: Bool {
        switch self {
        case .insideRun, .outsideRun, .counter, .toss, .draw, .screen, .qbSneak: return true
        default: return false
        }
    }

    var isPass: Bool {
        switch self {
        case .slant, .quickOut, .hitch, .flat, .drag,
             .curl, .dig, .seam, .cross, .postCorner, .comeback,
             .goRoute, .post, .corner, .flood, .bomb:
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
        case .slant:      return [.westCoast, .spread, .rpo, .proPassing, .airRaid]
        case .quickOut:   return [.westCoast, .airRaid, .rpo, .spread]
        case .hitch:      return [.westCoast, .airRaid, .proPassing, .rpo, .spread]
        case .flat:       return [.westCoast, .shanahan, .powerRun, .option]
        case .drag:       return [.westCoast, .spread, .rpo, .shanahan, .option]
        case .curl:       return [.westCoast, .proPassing, .airRaid]
        case .dig:        return [.airRaid, .proPassing, .spread, .westCoast, .shanahan]
        case .seam:       return [.airRaid, .spread, .rpo, .westCoast, .proPassing]
        case .cross:      return [.shanahan, .westCoast, .airRaid, .proPassing]
        case .postCorner: return [.airRaid, .proPassing, .powerRun]
        case .comeback:   return [.proPassing, .westCoast, .powerRun]
        case .goRoute:    return [.airRaid, .spread, .proPassing, .option]
        case .post:       return [.airRaid, .proPassing, .spread, .rpo, .shanahan]
        case .corner:     return [.airRaid, .shanahan, .proPassing]
        case .flood:      return [.shanahan, .airRaid, .proPassing, .westCoast]
        case .bomb:       return [.airRaid, .spread]
        case .qbSneak, .spike, .kneel: return OffensiveScheme.allCases
        }
    }

    /// Whether this play is part of the given scheme's installed playbook.
    func isInPlaybook(of scheme: OffensiveScheme?) -> Bool {
        guard let scheme else { return true }
        return schemes.contains(scheme)
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
    case cover2     = "Cover 2"
    case cover3     = "Cover 3"
    case cover4     = "Cover 4"
    case manToMan   = "Man Coverage"

    // Blitz package
    case noBlitz    = "No Blitz"
    case lbBlitz    = "LB Blitz"
    case dbBlitz    = "DB Blitz"
    case allOutBlitz = "All-Out Blitz"

    // Defensive front
    case base       = "Base 4-3"
    case nickel     = "Nickel"
    case dime       = "Dime"
    case goalLine   = "Goal Line"

    // MARK: Category

    var category: String {
        switch self {
        case .cover2, .cover3, .cover4, .manToMan:
            return "Coverage"
        case .noBlitz, .lbBlitz, .dbBlitz, .allOutBlitz:
            return "Blitz"
        case .base, .nickel, .dime, .goalLine:
            return "Front"
        }
    }

    // MARK: Simulator Modifiers

    /// How much this call adjusts the coverage quality seen by the offense.
    /// Positive values tighten coverage (reduces completion %).
    var coverageModifier: Double {
        switch self {
        case .cover2:     return 0.05
        case .cover3:     return 0.08
        case .cover4:     return 0.10
        case .manToMan:   return 0.12    // tightest, but vulnerable to big plays
        case .noBlitz:    return 0.02
        case .lbBlitz:    return 0.0
        case .dbBlitz:    return -0.04   // DB in blitz = less coverage help
        case .allOutBlitz:return -0.10
        case .base:       return 0.02
        case .nickel:     return 0.05
        case .dime:       return 0.08
        case .goalLine:   return -0.05   // heavy front, weaker pass coverage
        }
    }

    /// How much this call adds to the pass-rush pressure on the QB.
    /// Feeds into sack-chance and blitz-pickup calculations.
    var pressureModifier: Double {
        switch self {
        case .cover2, .cover3, .cover4, .manToMan: return 0.0
        case .noBlitz:    return 0.0
        case .lbBlitz:    return 0.06
        case .dbBlitz:    return 0.04
        case .allOutBlitz:return 0.12
        case .base:       return 0.02
        case .nickel:     return -0.02   // fewer DL
        case .dime:       return -0.04
        case .goalLine:   return 0.06
        }
    }

    /// How much this call improves run stopping.
    var runStopModifier: Double {
        switch self {
        case .cover2, .cover3, .cover4, .manToMan: return 0.0
        case .noBlitz, .lbBlitz, .dbBlitz, .allOutBlitz: return 0.0
        case .base:       return 0.08
        case .nickel:     return -0.05
        case .dime:       return -0.10
        case .goalLine:   return 0.18
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
enum DefensiveCall: String, CaseIterable, Identifiable {
    case cover3Base  = "Cover 3"
    case cover2Shell = "Cover 2 Shell"
    case quarters    = "Quarters"
    case manPress    = "Man Press"
    case lbFire      = "LB Blitz"
    case zoneBlitz   = "Zone Blitz"
    case cornerBlitz = "Corner Blitz"
    case allOut      = "All-Out Blitz"
    case goalLineD   = "Goal Line"
    case dimePrevent = "Dime Prevent"

    var id: String { rawValue }

    var package: DefensivePackage {
        switch self {
        case .cover3Base:  return DefensivePackage(coverage: .cover3, blitz: .noBlitz, front: .base)
        case .cover2Shell: return DefensivePackage(coverage: .cover2, blitz: .noBlitz, front: .base)
        case .quarters:    return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .nickel)
        case .manPress:    return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .nickel)
        case .lbFire:      return DefensivePackage(coverage: .cover3, blitz: .lbBlitz, front: .base)
        case .zoneBlitz:   return DefensivePackage(coverage: .cover2, blitz: .lbBlitz, front: .nickel)
        case .cornerBlitz: return DefensivePackage(coverage: .manToMan, blitz: .dbBlitz, front: .nickel)
        case .allOut:      return DefensivePackage(coverage: .manToMan, blitz: .allOutBlitz, front: .nickel)
        case .goalLineD:   return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        case .dimePrevent: return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .dime)
        }
    }

    /// One-line description shown under the call card.
    var blurb: String {
        switch self {
        case .cover3Base:  return "Three deep, four under — sound vs everything."
        case .cover2Shell: return "Two-high shell, corners squat on the flats."
        case .quarters:    return "Four deep. Nothing gets over the top."
        case .manPress:    return "Corners in their face — no free releases."
        case .lbFire:      return "Fire a backer through the A-gap."
        case .zoneBlitz:   return "Backer comes, coverage rotates behind it."
        case .cornerBlitz: return "Nickel screams in off the edge."
        case .allOut:      return "Everybody comes. Win the down right now."
        case .goalLineD:   return "Big bodies, zero cushion — stack the line."
        case .dimePrevent: return "Concede underneath, never the bomb."
        }
    }

    /// The defensive schemes whose playbook installs this call.
    var schemes: [DefensiveScheme] {
        switch self {
        case .cover3Base:  return DefensiveScheme.allCases
        case .cover2Shell: return [.tampa2, .base43, .multiple, .hybrid]
        case .quarters:    return [.tampa2, .multiple, .hybrid, .cover3]
        case .manPress:    return [.pressMan, .hybrid, .multiple]
        case .lbFire:      return [.base34, .base43, .multiple, .cover3]
        case .zoneBlitz:   return [.base34, .tampa2, .hybrid, .multiple]
        case .cornerBlitz: return [.pressMan, .multiple, .hybrid]
        case .allOut:      return [.pressMan, .multiple, .base34]
        case .goalLineD:   return DefensiveScheme.allCases
        case .dimePrevent: return DefensiveScheme.allCases
        }
    }

    func isInPlaybook(of scheme: DefensiveScheme?) -> Bool {
        guard let scheme else { return true }
        return schemes.contains(scheme)
    }
}
