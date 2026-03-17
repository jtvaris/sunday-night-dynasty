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
    case draw        = "Draw"
    case screen      = "Screen"

    // Short Pass (0-10 yards)
    case slant       = "Slant"
    case quickOut    = "Quick Out"
    case flat        = "Flat"
    case drag        = "Drag"

    // Medium Pass (11-20 yards)
    case curl        = "Curl"
    case dig         = "Dig"
    case postCorner  = "Post Corner"
    case comeback    = "Comeback"

    // Deep Pass (21+ yards)
    case goRoute     = "Go Route"
    case post        = "Post"
    case corner      = "Corner"
    case bomb        = "Bomb"

    // Special
    case qbSneak     = "QB Sneak"
    case spike       = "Spike"
    case kneel       = "Kneel"

    // MARK: Category

    /// The display category label shown in `PlayCallView`.
    var category: String {
        switch self {
        case .insideRun, .outsideRun, .draw, .screen:
            return "Run"
        case .slant, .quickOut, .flat, .drag:
            return "Short Pass"
        case .curl, .dig, .postCorner, .comeback:
            return "Medium Pass"
        case .goRoute, .post, .corner, .bomb:
            return "Deep Pass"
        case .qbSneak, .spike, .kneel:
            return "Special"
        }
    }

    // MARK: Type Flags

    var isRun: Bool {
        switch self {
        case .insideRun, .outsideRun, .draw, .screen, .qbSneak: return true
        default: return false
        }
    }

    var isPass: Bool {
        switch self {
        case .slant, .quickOut, .flat, .drag,
             .curl, .dig, .postCorner, .comeback,
             .goRoute, .post, .corner, .bomb:
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
        case .flat:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.25, yacMultiplier: 1.5)
        case .drag:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.1, yacMultiplier: 1.1)

        // --- Medium pass ---
        case .curl:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0, yacMultiplier: 0.9)
        case .dig:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.05, yacMultiplier: 1.0)
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
