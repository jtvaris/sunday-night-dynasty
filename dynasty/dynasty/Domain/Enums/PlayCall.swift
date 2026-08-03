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

    // ------------------------------------------------------------------
    // PERSISTENCE CONTRACT — read before editing this block.
    //
    // The `rawValue` of every case is save data: `Career.weeklyPracticePlayRaw`
    // (String?) and `Career.bonusInstalledPlaysRaw` ([String]) store it, and
    // both decode through `OffensivePlayCall(rawValue:)` (Career.swift:626/637).
    // Nothing anywhere persists a case INDEX or relies on `allCases` ordering,
    // so:
    //   • adding cases (anywhere in the declaration order) is safe,
    //   • RENAMING or REMOVING an existing rawValue silently drops a player's
    //     practiced / installed play on load. Never do it.
    // Declaration order is a pure presentation concern (it drives the card
    // order inside each category tab and `audibleOptions`).
    // ------------------------------------------------------------------

    // Run
    case insideRun   = "Inside Run"
    case insideZone  = "Inside Zone"
    case wideZone    = "Wide Zone"
    case outsideRun  = "Outside Run"
    case duo         = "Duo"
    case power       = "Power O"
    case counter     = "Counter"
    case trap        = "Trap"
    case toss        = "Toss Sweep"
    case draw        = "Draw"
    case zoneRead    = "Zone Read"
    case qbDraw      = "QB Draw"
    case dive        = "Goal Line Dive"
    case jetSweep    = "Jet Sweep"
    case endAround   = "End Around"
    case speedOption = "Speed Option"

    // Screen (simulated on the PASS path — see `PlaySimulator.playType(for:)`)
    case screen       = "Screen"
    case bubbleScreen = "Bubble Screen"
    case tunnelScreen = "Tunnel Screen"
    case slipScreen   = "Slip Screen"

    // Short Pass (0-10 yards)
    case slant        = "Slant"
    case quickOut     = "Quick Out"
    case hitch        = "Hitch"
    case flat         = "Flat"
    case drag         = "Drag"
    case stick        = "Stick"
    case mesh         = "Mesh"
    case spot         = "Spot"
    case snag         = "Snag"
    case shallowCross = "Shallow Cross"
    case angle        = "Angle Route"
    case fade         = "Back Pylon Fade"

    // Medium Pass (11-20 yards)
    case curl        = "Curl"
    case dig         = "Dig"
    case seam        = "TE Seam"
    case cross       = "Deep Cross"
    case postCorner  = "Post Corner"
    case comeback    = "Comeback"
    case wheel       = "Wheel"
    case levels      = "Levels"
    case yCross      = "Y-Cross"
    case dagger      = "Dagger"
    case sail        = "Sail"
    case smash       = "Smash"

    // Deep Pass (21+ yards)
    case goRoute      = "Go Route"
    case post         = "Post"
    case corner       = "Corner"
    case flood        = "Flood"
    case bomb         = "Bomb"
    case fourVerts    = "Four Verticals"
    case sluggo       = "Sluggo"
    case backShoulder = "Back Shoulder"

    // Play Action (every case here sets `isPlayAction` — it gates the
    // box-bite roll and the keyed-PA punish in `PlaySimulator`)
    case playActionDeep = "Play Action Deep"
    case paBoot         = "PA Boot"
    case paCross        = "PA Deep Cross"
    case paGlance       = "PA Glance"

    // RPO — represented as quick passes off a run fake (the engine has no
    // give/pull mechanic; the "give" side lives in the same formation family's
    // zone runs, reachable through the audible strip).
    case rpoBubble   = "RPO Bubble"
    case rpoSlant    = "RPO Slant"
    case rpoStick    = "RPO Stick"
    case rpoPop      = "RPO Pop Pass"

    // Special
    case qbSneak     = "QB Sneak"
    case tushPush    = "Push Sneak"
    case spike       = "Spike"
    case kneel       = "Kneel"
    case hailMary    = "Hail Mary"

    // MARK: Category

    /// The display category label shown in `PlayCallView`.
    var category: String {
        switch self {
        case .insideRun, .insideZone, .wideZone, .outsideRun, .duo, .power,
             .counter, .trap, .toss, .draw, .zoneRead, .qbDraw, .dive,
             .jetSweep, .endAround, .speedOption:
            return "Run"
        case .screen, .bubbleScreen, .tunnelScreen, .slipScreen:
            return "Screen"
        case .slant, .quickOut, .hitch, .flat, .drag, .stick, .mesh,
             .spot, .snag, .shallowCross, .angle, .fade:
            return "Short Pass"
        case .curl, .dig, .seam, .cross, .postCorner, .comeback, .wheel,
             .levels, .yCross, .dagger, .sail, .smash:
            return "Medium Pass"
        case .goRoute, .post, .corner, .flood, .bomb,
             .fourVerts, .sluggo, .backShoulder:
            return "Deep Pass"
        case .playActionDeep, .paBoot, .paCross, .paGlance:
            return "Play Action"
        case .rpoBubble, .rpoSlant, .rpoStick, .rpoPop:
            return "RPO"
        case .qbSneak, .tushPush, .spike, .kneel, .hailMary:
            return "Special"
        }
    }

    /// The full ordered tab list the call sheet renders, in call-sheet order.
    /// Single source for every consumer (UI tabs, AI category fallbacks).
    static let categories: [String] = [
        "Run", "Screen", "Short Pass", "Medium Pass", "Deep Pass",
        "Play Action", "RPO", "Special"
    ]

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

        // --- Playbook expansion ---
        case .insideZone:  return "Press the front side, one cut, get north."
        case .wideZone:    return "Stretch the whole front, bend it back if they overrun."
        case .duo:         return "Double team everything, back reads the backer."
        case .power:       return "Down block, kick out, guard leads through the hole."
        case .trap:        return "Let him through, then bury him with the backside guard."
        case .zoneRead:    return "Read the end — give it or keep it, he can't have both."
        case .qbDraw:      return "Drop back, then run it right at the vacated middle."
        case .endAround:   return "Receiver comes back the other way at full speed."
        case .speedOption: return "Attack the edge and make the end wrong."
        case .bubbleScreen: return "Ball out now — let the slot run behind his blockers."
        case .tunnelScreen: return "Bring him back inside behind a wall of blockers."
        case .slipScreen:   return "Back slips out of protection into open grass."
        case .spot:         return "Corner, flat, and a man sitting in the hole."
        case .snag:         return "Slide inside, pull the flat defender two ways."
        case .shallowCross: return "Run him flat across the field and let him go."
        case .angle:        return "Back sells the flat, then snaps back inside the backer."
        case .fade:         return "Put it where only he can get it, back corner."
        case .levels:       return "Two in-cuts at two depths — pick a level."
        case .yCross:       return "Tight end runs the whole field, everything else clears."
        case .dagger:       return "Seam clears the hook, dig comes in behind it."
        case .sail:         return "Three-level stretch to the boundary."
        case .smash:        return "Hitch under, corner over — high-low the flat corner."
        case .fourVerts:    return "Four straight lines. Somebody wins one."
        case .sluggo:       return "Sell the slant all day, then run right past him."
        case .backShoulder: return "Throw it where the corner isn't — he comes back to it."
        case .paBoot:       return "Fake it, roll away from the pressure, take what's there."
        case .paCross:      return "Suck the backers up, run the crosser behind them."
        case .paGlance:     return "One-step fake, glance route off the safety's eyes."
        case .rpoBubble:    return "Count the box — if they're light, the bubble is free."
        case .rpoSlant:     return "Read the backer: he steps up, the slant is open."
        case .rpoStick:     return "Handoff or stick route — the flat defender decides."
        case .rpoPop:       return "Sell the dive, pop it over the crashing linebacker."
        case .tushPush:     return "Everybody push. One yard, no drama."
        case .hailMary:     return "Everybody to the end zone. Throw it up."
        }
    }

    // MARK: Type Flags

    /// True for hand-off / carry plays. NOTE the one legacy wart: `.screen` is
    /// `isRun == true` but is simulated on the PASS path (see
    /// `PlaySimulator.playType(for:)`). The NEW screens deliberately do not
    /// repeat it — they are honest passes, which also lets them survive the
    /// long-yardage run filter in `AdaptiveOpponentAI.offensiveCounter`.
    var isRun: Bool {
        switch self {
        case .insideRun, .insideZone, .wideZone, .outsideRun, .duo, .power,
             .counter, .trap, .toss, .draw, .zoneRead, .qbDraw, .screen,
             .dive, .jetSweep, .endAround, .speedOption, .qbSneak, .tushPush:
            return true
        default: return false
        }
    }

    var isPass: Bool {
        switch self {
        case .bubbleScreen, .tunnelScreen, .slipScreen,
             .slant, .quickOut, .hitch, .flat, .drag, .stick, .mesh,
             .spot, .snag, .shallowCross, .angle, .fade,
             .curl, .dig, .seam, .cross, .postCorner, .comeback, .wheel,
             .levels, .yCross, .dagger, .sail, .smash,
             .goRoute, .post, .corner, .flood, .bomb,
             .fourVerts, .sluggo, .backShoulder,
             .playActionDeep, .paBoot, .paCross, .paGlance,
             .rpoBubble, .rpoSlant, .rpoStick, .rpoPop,
             .hailMary:
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
    /// Inverted from the authoritative per-scheme install lists in `Playbook`
    /// (a play belongs to a scheme iff that scheme's install list names it).
    /// `qbSneak` / `spike` / `kneel` are universal situational calls.
    var schemes: [OffensiveScheme] { Playbook.schemes(installing: self) }

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
        case pistol      // QB 4 yд deep, back beside him — the read/RPO set
        case playAction  // under centre, back on a downhill fake track
        case special     // spike/kneel — never audibled into or out of
    }

    /// The alignment family this call snaps from (see `FormationFamily`).
    ///
    /// Deliberately EXHAUSTIVE (no `default:`): the old fallthrough silently
    /// dropped unlisted calls into `.baseGun`, which both mis-aligned the 3D
    /// formation and quietly widened the audible strip. A new case must now be
    /// placed by hand or the compiler stops the build.
    var formationFamily: FormationFamily {
        switch self {
        case .insideRun, .insideZone, .duo, .power, .trap, .dive,
             .qbSneak, .tushPush:
            return .iForm
        case .outsideRun, .wideZone, .jetSweep, .endAround:
            return .stretch
        case .draw, .screen, .slipScreen:
            return .backfield
        case .slant, .quickOut, .flat, .drag, .stick, .mesh,
             .spot, .snag, .shallowCross, .angle, .fade,
             .bubbleScreen, .tunnelScreen:
            return .quick
        case .cross, .yCross:
            return .crossSet
        case .goRoute, .post, .corner, .bomb,
             .fourVerts, .sluggo, .backShoulder, .hailMary:
            return .spreadDeep
        case .zoneRead, .qbDraw, .speedOption,
             .rpoBubble, .rpoSlant, .rpoStick, .rpoPop:
            return .pistol
        case .playActionDeep, .paBoot, .paCross, .paGlance:
            return .playAction
        case .spike, .kneel:
            return .special
        case .counter, .toss, .hitch, .curl, .dig, .seam, .postCorner,
             .comeback, .wheel, .levels, .dagger, .sail, .smash, .flood:
            return .baseGun
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
            // Rubs, crossers and double moves shake man coverage.
            return [.drag, .mesh, .cross, .slant, .wheel, .jetSweep,
                    .shallowCross, .angle, .sluggo, .backShoulder,
                    .endAround, .speedOption, .fade, .yCross].contains(self)
        case .cover1:
            // Attack the lone deep safety.
            return [.post, .goRoute, .bomb, .playActionDeep, .cross,
                    .paCross, .fourVerts, .sluggo, .dagger, .yCross].contains(self)
        case .cover2:
            // The seams and the deep middle split a two-high shell.
            return [.seam, .post, .dig, .corner, .cross,
                    .fourVerts, .dagger, .levels, .smash].contains(self)
        case .cover3:
            // Out-breaking timing throws beat the three-deep zone.
            return [.quickOut, .flat, .comeback, .curl, .stick,
                    .smash, .sail, .snag, .spot, .backShoulder].contains(self)
        case .cover4:
            // Quarters gives the ground game and the flats away.
            return [.insideRun, .outsideRun, .counter, .toss, .flat, .drag,
                    .insideZone, .duo, .power, .trap, .zoneRead,
                    .rpoBubble, .rpoStick, .tushPush].contains(self)
        case .prevent:
            // Take the free underneath yards.
            return [.slant, .hitch, .drag, .screen, .draw, .insideRun,
                    .insideZone, .duo, .qbDraw, .slipScreen, .bubbleScreen].contains(self)
        case .tampa2:
            // The Mike carries the pipe — attack the sidelines instead.
            return [.sail, .smash, .corner, .fade, .wideZone, .endAround].contains(self)
        case .cover6:
            // Split-field: hit the run game and the middle the check leaves open.
            return [.insideZone, .power, .mesh, .shallowCross, .snag].contains(self)
        case .cover0:
            // Zero help behind it — get the ball out, or run right past it.
            return [.bubbleScreen, .tunnelScreen, .slipScreen, .rpoBubble,
                    .sluggo, .fourVerts].contains(self)
        default:
            return false
        }
    }

    // MARK: Designed Carrier

    /// Who the DESIGN hands the ball to on a run call.
    ///
    /// Most runs are the back's. Four calls are the quarterback's by design
    /// (the sneaks, the QB draw, the speed option) and one is a receiver's
    /// (the end around). This is the SINGLE source of truth both halves of
    /// the engine read: `PlaySimulator` credits the rushing stats and the
    /// play-by-play line to this man, and the 3D field hands him the ball —
    /// so the box score, the feed and the choreography can never name three
    /// different players on the same snap.
    ///
    /// It mirrors `RouteSpec.spec(for:).carrierRole` exactly (role 0 = QB,
    /// role 7 = WR-L, everything else the back); the spec owns the GEOMETRY
    /// of his track, this owns WHO he is.
    enum DesignedRusher {
        /// The starting back (every ordinary carry — and every pass call).
        case back
        /// The quarterback keeps it: sneak, push, QB draw, speed option.
        case quarterback
        /// The receiver comes back the other way at speed: the end around.
        case receiver
    }

    /// The designed ball-carrier for this call (see `DesignedRusher`).
    /// A pass call has no designed carry, so it reports `.back` — the value
    /// only ever matters on the simulator's run path.
    var designedRusher: DesignedRusher {
        switch self {
        // RouteSpec carrierRole 0 — the QB's own track is the carry.
        // (`zoneRead` deliberately stays with the back: its spec draws BOTH
        // halves of the read but names the give, and the sim has no pull.)
        case .qbSneak, .tushPush, .qbDraw, .speedOption:
            return .quarterback
        // RouteSpec carrierRole 7 — the WR takes it going the other way.
        // (`jetSweep` is NOT here: its spec motions the slot as a decoy and
        // hands the sweep to the back, carrierRole 1.)
        case .endAround:
            return .receiver
        default:
            return .back
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
        /// Balance R3 fix — perimeter weight (0 = interior). Stretch/toss/jet
        /// runs win on the EDGE, where the back's speed matters once the OL
        /// seals the crease. `PlaySimulator` adds an edge-crease yard term
        /// scaled by this factor, gated on the blocking crease (so a burner
        /// still needs a lane). 0 for every interior run → inside runs and the
        /// RB×OL ordering cells stay byte-identical.
        var edgeFactor: Double = 0

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
            // Stretch to the edge: perimeter yards gated on sealing the edge.
            return SimulatorHint(passDepth: nil, runGapBonus: -0.05, blitzPickupBonus: 0, yacMultiplier: 1.3, edgeFactor: 0.85)
        case .counter:
            // Misdirection: interior gap credit once the pursuit over-flows
            return SimulatorHint(passDepth: nil, runGapBonus: 0.1, blitzPickupBonus: 0, yacMultiplier: 1.15)
        case .toss:
            // Edge speed: boom-or-bust to the perimeter
            return SimulatorHint(passDepth: nil, runGapBonus: -0.1, blitzPickupBonus: 0, yacMultiplier: 1.45, edgeFactor: 1.05)
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
            return SimulatorHint(passDepth: nil, runGapBonus: -0.15, blitzPickupBonus: 0.05, yacMultiplier: 1.6, edgeFactor: 1.20)

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

        // ==============================================================
        // Playbook expansion. Every play below is expressed ONLY in the six
        // existing scalars — there is no seventh knob, and design intent
        // ("risk profile", "protection", "target profile") is encoded through
        // them:
        //   • consistency  = high runGapBonus + low yacMultiplier
        //   • explosiveness= negative runGapBonus + high edgeFactor / yac
        //   • protection   = blitzPickupBonus (positive = ball out early,
        //                    negative = the hold time is the cost)
        // ==============================================================

        // --- Expansion: zone / gap runs ---
        case .insideZone:
            // One-cut zone: reliable interior credit, modest run-after.
            return SimulatorHint(passDepth: nil, runGapBonus: 0.14, blitzPickupBonus: 0,
                                 yacMultiplier: 1.05)
        case .wideZone:
            // Stretch the front and bend it back: the edge decides it.
            return SimulatorHint(passDepth: nil, runGapBonus: -0.04, blitzPickupBonus: 0,
                                 yacMultiplier: 1.35, edgeFactor: 0.95)
        case .duo:
            return SimulatorHint(passDepth: nil, runGapBonus: 0.20, blitzPickupBonus: 0,
                                 yacMultiplier: 0.95)
        case .power:
            // The pulling guard is a body OUT of protection — hence the −0.05.
            return SimulatorHint(passDepth: nil, runGapBonus: 0.22, blitzPickupBonus: -0.05,
                                 yacMultiplier: 1.00)
        case .trap:
            return SimulatorHint(passDepth: nil, runGapBonus: 0.18, blitzPickupBonus: 0,
                                 yacMultiplier: 1.20)

        // --- Expansion: QB-conflict runs ---
        case .zoneRead:
            // The read IS the protection: the unblocked end is accounted for.
            return SimulatorHint(passDepth: nil, runGapBonus: 0.08, blitzPickupBonus: 0.10,
                                 yacMultiplier: 1.25, edgeFactor: 0.45)
        case .qbDraw:
            return SimulatorHint(passDepth: nil, runGapBonus: 0.06, blitzPickupBonus: 0.15,
                                 yacMultiplier: 1.30, edgeFactor: 0.20)
        case .endAround:
            // Boom-or-bust perimeter: nothing interior, everything on the edge.
            return SimulatorHint(passDepth: nil, runGapBonus: -0.18, blitzPickupBonus: 0.05,
                                 yacMultiplier: 1.55, edgeFactor: 1.25)
        case .speedOption:
            return SimulatorHint(passDepth: nil, runGapBonus: -0.12, blitzPickupBonus: 0,
                                 yacMultiplier: 1.40, edgeFactor: 1.15)

        // --- Expansion: screens (pass path, blitz beaters, max YAC) ---
        case .bubbleScreen:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.30,
                                 yacMultiplier: 1.70)
        case .tunnelScreen:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.25,
                                 yacMultiplier: 1.85)
        case .slipScreen:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.22,
                                 yacMultiplier: 1.75)

        // --- Expansion: short pass ---
        case .spot:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.22,
                                 yacMultiplier: 0.95)
        case .snag:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.20,
                                 yacMultiplier: 1.00)
        case .shallowCross:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.12,
                                 yacMultiplier: 1.45)
        case .angle:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.18,
                                 yacMultiplier: 1.35)
        case .fade:
            // The one short call that is NOT a blitz beater: no YAC, no easy
            // outlet — it lives or dies on the WR-vs-CB completion roll.
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.10,
                                 yacMultiplier: 0.60)

        // --- Expansion: medium pass ---
        case .levels:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0,
                                 yacMultiplier: 1.05)
        case .yCross:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.05,
                                 yacMultiplier: 1.30)
        case .dagger:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.08,
                                 yacMultiplier: 1.10)
        case .sail:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0.05,
                                 yacMultiplier: 1.00)
        case .smash:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0,
                                 yacMultiplier: 0.90)

        // --- Expansion: deep pass ---
        case .fourVerts:
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.18,
                                 yacMultiplier: 1.05)
        case .sluggo:
            // The double move — the hold time is the price of the shot.
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.20,
                                 yacMultiplier: 1.15)
        case .backShoulder:
            // Contested and caught flat-footed: the answer to press, no YAC.
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.12,
                                 yacMultiplier: 0.55)

        // --- Expansion: play action ---
        case .paBoot:
            // The ONLY play-action call with positive protection credit: the
            // rollout moves the launch point away from the rush.
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: 0.15,
                                 yacMultiplier: 1.25, isPlayAction: true)
        case .paCross:
            return SimulatorHint(passDepth: .medium, runGapBonus: 0, blitzPickupBonus: -0.10,
                                 yacMultiplier: 1.35, isPlayAction: true)
        case .paGlance:
            return SimulatorHint(passDepth: .short, runGapBonus: 0, blitzPickupBonus: 0.10,
                                 yacMultiplier: 1.20, isPlayAction: true)

        // --- Expansion: RPO ---
        // The ball is out before the read defender can matter, hence the very
        // high pickup. `runGapBonus` is INERT on the pass path (it is only read
        // by the run resolver) — it is carried so the two-point conversion path
        // (`runGapBonus * 0.3`) and any future give/pull branch behave sanely.
        case .rpoBubble:
            return SimulatorHint(passDepth: .short, runGapBonus: 0.10, blitzPickupBonus: 0.28,
                                 yacMultiplier: 1.55)
        case .rpoSlant:
            return SimulatorHint(passDepth: .short, runGapBonus: 0.10, blitzPickupBonus: 0.25,
                                 yacMultiplier: 1.25)
        case .rpoStick:
            return SimulatorHint(passDepth: .short, runGapBonus: 0.10, blitzPickupBonus: 0.24,
                                 yacMultiplier: 1.00)
        case .rpoPop:
            return SimulatorHint(passDepth: .short, runGapBonus: 0.10, blitzPickupBonus: 0.20,
                                 yacMultiplier: 1.30)

        // --- Expansion: special ---
        case .tushPush:
            // Highest gap credit in the game (qbSneak = 0.30) with the lowest
            // YAC: a near-guaranteed yard that can never break.
            return SimulatorHint(passDepth: nil, runGapBonus: 0.38, blitzPickupBonus: 0,
                                 yacMultiplier: 0.55)
        case .hailMary:
            return SimulatorHint(passDepth: .deep, runGapBonus: 0, blitzPickupBonus: -0.25,
                                 yacMultiplier: 1.00)
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
    case tampa2     = "Tampa 2"
    case cover6     = "Cover 6"
    case cover0     = "Cover 0"
    case manToMan   = "Man Coverage"
    case prevent    = "Prevent"

    // Blitz package
    case noBlitz    = "No Blitz"
    case lbBlitz    = "LB Blitz"
    case doubleAGap = "Double A-Gap"
    case fireZone   = "Fire Zone"
    case simPressure = "Sim Pressure"
    case safetyBlitz = "Safety Blitz"
    case dbBlitz    = "DB Blitz"
    case allOutBlitz = "All-Out Blitz"

    // Defensive front
    case base       = "Base 4-3"
    case odd34      = "3-4 Front"
    case nickel     = "Nickel"
    case bigNickel  = "Big Nickel"
    case dime       = "Dime"
    case bear       = "Bear Front"
    case goalLine   = "Goal Line"

    // MARK: Category

    var category: String {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .tampa2, .cover6, .cover0,
             .manToMan, .prevent:
            return "Coverage"
        case .noBlitz, .lbBlitz, .doubleAGap, .fireZone, .simPressure,
             .safetyBlitz, .dbBlitz, .allOutBlitz:
            return "Blitz"
        case .base, .odd34, .nickel, .bigNickel, .dime, .bear, .goalLine:
            return "Front"
        }
    }

    /// True for the shells the simulator treats as assigned MAN coverage
    /// (individual WR-vs-CB matchup, press release / jam branch). `cover0` is
    /// man with zero deep help, so it belongs here alongside `manToMan`;
    /// `tampa2` / `cover6` are zone and deliberately do not.
    var isManCoverage: Bool {
        self == .manToMan || self == .cover0
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
        case .tampa2:     return 0.07    // sound zone; pays for the pipe in the flats
        case .cover6:     return 0.09    // split-field check: right answer both ways
        case .cover0:     return 0.14    // tightest raw coverage in the game...
        case .manToMan:   return 0.12    // tightest, but vulnerable to big plays
        case .prevent:    return 0.04    // soft overall; the depth shading does the work
        case .noBlitz:    return 0.02
        case .lbBlitz:    return 0.0
        case .doubleAGap: return -0.06   // both backers vacate the middle
        case .fireZone:   return -0.01   // 5 rush, 3 deep / 3 under — nearly sound
        case .simPressure:return 0.01    // shows heat, rushes four: coverage stays whole
        case .safetyBlitz:return -0.06   // the deep net loses a defender
        case .dbBlitz:    return -0.04   // DB in blitz = less coverage help
        case .allOutBlitz:return -0.10
        case .base:       return 0.02
        case .odd34:      return 0.01
        case .nickel:     return 0.05
        case .bigNickel:  return 0.06    // third safety: cover people, still fit the run
        case .dime:       return 0.08
        case .bear:       return -0.04   // heavy box, light secondary help
        case .goalLine:   return -0.05   // heavy front, weaker pass coverage
        }
    }

    /// How much this call adds to the pass-rush pressure on the QB.
    /// Feeds into sack-chance and blitz-pickup calculations.
    var pressureModifier: Double {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .tampa2, .cover6, .manToMan:
            return 0.0
        case .cover0:     return 0.04    // no help = everyone else can come
        case .prevent:    return -0.02   // rush three, everyone else drops
        case .noBlitz:    return 0.0
        case .lbBlitz:    return 0.06
        case .doubleAGap: return 0.10    // interior heat right up the middle
        case .fireZone:   return 0.07    // the sound five-man pressure
        case .simPressure:return 0.05    // creeper: shows heat, still rushes four
        case .safetyBlitz:return 0.08
        case .dbBlitz:    return 0.04
        case .allOutBlitz:return 0.12
        case .base:       return 0.02
        case .odd34:      return 0.03    // two-gap front frees the backers up
        case .nickel:     return -0.02   // fewer DL
        case .bigNickel:  return -0.01
        case .dime:       return -0.04
        case .bear:       return 0.05    // extra bodies crowd the line
        case .goalLine:   return 0.06
        }
    }

    /// How much this call improves run stopping.
    var runStopModifier: Double {
        switch self {
        case .cover1, .cover2, .cover3, .cover4, .tampa2, .cover6, .manToMan:
            return 0.0
        case .cover0:     return 0.03    // every defender is downhill on the run
        case .prevent:    return -0.06   // soft shell concedes the ground game
        case .noBlitz, .lbBlitz, .dbBlitz, .allOutBlitz: return 0.0
        case .doubleAGap: return 0.04    // mugged-up backers plug the middle
        case .fireZone:   return 0.01
        case .simPressure:return -0.01   // the dropping end vacates his gap
        case .safetyBlitz:return 0.02
        case .base:       return 0.0     // B2a: a plain base front no longer
                                         // nerfs the neutral run (the neutral
                                         // point is now set by B1, not the front)
        case .odd34:      return 0.06    // two-gap the odd front
        case .nickel:     return -0.05
        case .bigNickel:  return -0.02   // a safety, not a backer, fits the alley
        case .dime:       return -0.10
        case .bear:       return 0.14    // 46-style front swallows interior runs
        case .goalLine:   return 0.18
        }
    }

    // MARK: Shell Audibles (R36)

    /// The coverage shells a defensive audible can rotate into at the line
    /// (prevent stays a situational call — never an audible target, and neither
    /// is `cover0`: committing to zero help is a call, not a check).
    static let audibleShells: [DefensivePlayCall] = [
        .cover1, .cover2, .cover3, .cover4, .tampa2, .cover6, .manToMan
    ]

    /// Short chip label for the shell-audible strip.
    var shellShortLabel: String {
        switch self {
        case .manToMan: return "Man"
        case .cover4:   return "Quarters"
        case .tampa2:   return "Tampa 2"
        case .cover6:   return "Cover 6"
        case .cover0:   return "Zero"
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
        case .tampa2:  return 0.05   // the Mike carries the deep middle
        case .cover6:  return 0.02
        case .cover0:  return -0.12  // the mirror of prevent: nothing behind it
        default:       return 0
        }
    }

    /// Extra completion penalty applied ONLY to short throws — negative
    /// values make the checkdown easier (prevent gives the underneath away).
    var shortCoverageModifier: Double {
        switch self {
        case .prevent: return -0.08
        case .tampa2:  return -0.03  // the price of the pipe is the flats
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
    case tampa2      = "Tampa 2"
    case cover6      = "Cover 6"
    case cloud2      = "Cloud 2"
    case prevent     = "Prevent"

    // Pressure (blitzes)
    case lbFire      = "LB Blitz"
    case doubleAGap  = "Double A-Gap"
    case zoneBlitz   = "Zone Blitz"
    case fireZone    = "Fire Zone"
    case simPressure = "Sim Pressure"
    case creeper     = "Nickel Creeper"
    case safetyBlitz = "Safety Blitz"
    case cornerBlitz = "Corner Blitz"
    case edgeDog     = "Edge Dog"
    case overload    = "Overload"
    case dimeFire    = "Dime Fire"
    case cover0      = "Cover 0"
    case allOut      = "All-Out Blitz"

    // Man (man-to-man shells)
    case manPress     = "Man Press"
    case manFree      = "Man Free"
    case twoManUnder  = "2-Man Under"
    case twoManPress  = "2-Man Press"
    case cover1Robber = "Cover 1 Robber"

    // Packages (personnel groupings)
    case nickelPackage = "Nickel"
    case dimePackage   = "Dime"
    case goalLineD     = "Goal Line"
    case bearFront     = "Bear Front"
    case base34        = "3-4 Base"
    case bigNickel     = "Big Nickel"

    var id: String { rawValue }

    /// The clipboard category tab this call lives under.
    var category: String {
        switch self {
        case .cover1, .cover2Shell, .cover3Base, .quarters, .cover4Match,
             .tampa2, .cover6, .cloud2, .prevent:
            return "Coverage"
        case .lbFire, .doubleAGap, .zoneBlitz, .fireZone, .simPressure, .creeper,
             .safetyBlitz, .cornerBlitz, .edgeDog, .overload, .dimeFire,
             .cover0, .allOut:
            return "Pressure"
        case .manPress, .manFree, .twoManUnder, .twoManPress, .cover1Robber:
            return "Man"
        case .nickelPackage, .dimePackage, .goalLineD, .bearFront, .base34, .bigNickel:
            return "Packages"
        }
    }

    /// The ordered clipboard tabs (unchanged by the expansion — every new call
    /// lands in one of the four existing categories).
    static let categories: [String] = ["Coverage", "Pressure", "Man", "Packages"]

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

        // --- Playbook expansion ---
        case .tampa2:      return DefensivePackage(coverage: .tampa2, blitz: .noBlitz, front: .base)
        case .cover6:      return DefensivePackage(coverage: .cover6, blitz: .noBlitz, front: .nickel)
        case .cloud2:      return DefensivePackage(coverage: .cover2, blitz: .noBlitz, front: .bigNickel)
        case .cover1Robber:return DefensivePackage(coverage: .cover1, blitz: .noBlitz, front: .bigNickel)
        case .twoManPress: return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .bigNickel)
        case .cover0:      return DefensivePackage(coverage: .cover0, blitz: .allOutBlitz, front: .nickel)
        case .fireZone:    return DefensivePackage(coverage: .cover3, blitz: .fireZone, front: .base)
        case .simPressure: return DefensivePackage(coverage: .cover4, blitz: .simPressure, front: .nickel)
        case .creeper:     return DefensivePackage(coverage: .cover3, blitz: .simPressure, front: .bigNickel)
        case .edgeDog:     return DefensivePackage(coverage: .cover1, blitz: .lbBlitz, front: .nickel)
        case .overload:    return DefensivePackage(coverage: .manToMan, blitz: .safetyBlitz, front: .bigNickel)
        case .dimeFire:    return DefensivePackage(coverage: .cover2, blitz: .dbBlitz, front: .dime)
        case .base34:      return DefensivePackage(coverage: .cover3, blitz: .noBlitz, front: .odd34)
        case .bigNickel:   return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .bigNickel)
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

        // --- Playbook expansion ---
        case .tampa2:      return "Two deep, and the Mike runs the pipe."
        case .cover6:      return "Quarters to the field, half to the boundary."
        case .cloud2:      return "Corner caps the flat, safety takes the deep half."
        case .cover1Robber:return "Man everywhere, one thief sitting on the dig."
        case .twoManPress: return "Jam them at the line, two safeties over the top."
        case .cover0:      return "Zero help. Everybody covers, everybody else comes."
        case .fireZone:    return "Five come, a lineman drops — three deep behind it."
        case .simPressure: return "Show the house, rush four, keep the coverage whole."
        case .creeper:     return "Backer creeps late, the end drops out behind him."
        case .edgeDog:     return "Both edges dog it — squeeze the pocket from outside."
        case .overload:    return "Load one side. Make the back block a safety."
        case .dimeFire:    return "Six DBs, and one of them is coming."
        case .base34:      return "Two-gap the odd front, backers run free."
        case .bigNickel:   return "Third safety in — cover the tight end, still play the run."
        }
    }

    /// The defensive schemes whose playbook installs this call — inverted from
    /// the authoritative per-scheme install lists in `Playbook`.
    var schemes: [DefensiveScheme] { Playbook.schemes(installing: self) }

    func isInPlaybook(of scheme: DefensiveScheme?) -> Bool {
        guard let scheme else { return true }
        return schemes.contains(scheme)
    }
}
