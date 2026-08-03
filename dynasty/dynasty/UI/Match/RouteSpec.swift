import Foundation
import CoreGraphics

// MARK: - Route Spec (single source of truth for play geometry)

/// The designed pattern of one offensive play call: a waypoint route per
/// skill role, the primary read, and the ball-carrier's track on runs.
///
/// This is the ONE truth for play shapes — `PlayChoreographer` runs the 3D
/// field from it and `PlayDiagramView` draws the X&O card from it (the card
/// is a 2D projection of the same spec), so the chalkboard and the field can
/// never disagree.
///
/// Waypoint space is LOS-relative and side-mirrored:
/// - `depth`: yards past the line of scrimmage (negative = backfield).
/// - `lateral`: cumulative offset from the player's own alignment, where
///   POSITIVE runs toward his own sideline (outside) and NEGATIVE cuts
///   inside / across the field. A player aligned left of the ball mirrors
///   automatically, so one table serves both sides.
///
/// Role contract matches the choreographer: 0=QB, 1=RB, 7=WR-L, 8=WR-R,
/// 9=slot, 10=TE. A skill role with no entry in `routes` stays in to block.
struct RouteSpec {

    struct Waypoint {
        var depth: Float
        var lateral: Float

        init(_ depth: Float, _ lateral: Float) {
            self.depth = depth
            self.lateral = lateral
        }
    }

    /// Route waypoints per offense role. Missing role = blocking assignment.
    var routes: [Int: [Waypoint]]
    /// The design's primary read / ball-carrier — gold on the play card.
    var primaryRole: Int
    /// Ball-carrier role on run plays (0 = QB keeps it).
    var carrierRole: Int?
    /// Role that goes in PRE-SNAP motion (jet sweep) before the ball moves.
    var motionRole: Int?

    init(routes: [Int: [Waypoint]], primaryRole: Int,
         carrierRole: Int? = nil, motionRole: Int? = nil) {
        self.routes = routes
        self.primaryRole = primaryRole
        self.carrierRole = carrierRole
        self.motionRole = motionRole
    }

    // MARK: World Mapping

    /// Maps a waypoint list into field space from a player's alignment.
    /// `direction` is +1 when the offense drives toward +Z. `depthScale`
    /// stretches/squeezes route depth gently (fit the simulated catch depth).
    /// The SAME function feeds the 3D field and the 2D card.
    /// `mirror` (±1) is the coach's REVERSE flip, offense-relative. It arrives
    /// having ALREADY reflected the alignment X in `offensePositions`, so
    /// `startX` here is the reflected start. To pick the correct "his sideline"
    /// we recover the canonical (pre-reflection) alignment with `startX * mirror`
    /// (mirror·mirror = 1), then reflect the lateral DISPLACEMENT by the same
    /// `mirror` — this is what flips a CENTERED carrier (x=0) whose alignment
    /// alone would not move. `mirror == 1` is byte-for-byte the old behavior.
    static func resolve(_ waypoints: [Waypoint], startX: Float, startZ: Float,
                        losZ: Float, direction: Float,
                        depthScale: Float = 1, mirror: Float = 1) -> [(x: Float, z: Float)] {
        // Which sideline is "his": alignment left of the ball mirrors laterals.
        let canonicalStartX = startX * mirror
        let sideSign: Float = canonicalStartX < -0.5 ? -1 : 1
        var points: [(x: Float, z: Float)] = [(startX, startZ)]
        for waypoint in waypoints {
            points.append((startX + waypoint.lateral * sideSign * mirror,
                           losZ + direction * waypoint.depth * depthScale))
        }
        return points
    }

    /// Field-space polyline for one role (alignment start included), or nil
    /// when the role blocks on this play.
    func points(role: Int, startX: Float, startZ: Float, losZ: Float,
                direction: Float, depthScale: Float = 1,
                mirror: Float = 1) -> [(x: Float, z: Float)]? {
        guard let waypoints = routes[role] else { return nil }
        return RouteSpec.resolve(waypoints, startX: startX, startZ: startZ,
                                 losZ: losZ, direction: direction,
                                 depthScale: depthScale, mirror: mirror)
    }

    // MARK: The Playbook

    /// The route map for every offensive call. Depths/laterals in yards.
    static func spec(for call: OffensivePlayCall) -> RouteSpec {
        typealias W = Waypoint
        switch call {

        // --- Runs (carrier track + clears/stalks where they matter) ---
        case .insideRun:
            return RouteSpec(routes: [1: [W(-1.0, -1.2), W(2, -1.5), W(7, -1.0)]],
                             primaryRole: 1, carrierRole: 1)
        case .outsideRun:
            return RouteSpec(routes: [1: [W(-1.5, 3), W(0.5, 6.5), W(4, 8.5), W(9, 9)]],
                             primaryRole: 1, carrierRole: 1)
        case .counter:
            // Jab step away, then the cutback behind the pulling guard.
            return RouteSpec(routes: [1: [W(-1.8, 2), W(-1.2, -3), W(1.5, -4.5), W(7, -4)]],
                             primaryRole: 1, carrierRole: 1)
        case .toss:
            return RouteSpec(routes: [1: [W(-2.5, 4.5), W(-0.5, 8.5), W(3, 10.5), W(9, 11.5)]],
                             primaryRole: 1, carrierRole: 1)
        case .draw:
            // Late mesh at the QB's drop, then straight up the vacated middle;
            // the receivers sprint clears to sell the dropback.
            return RouteSpec(routes: [
                1: [W(-5.6, -1.2), W(1, -1.6), W(7, -1.2)],
                7: [W(14, 0)], 8: [W(14, 0)], 9: [W(8, -1)],
            ], primaryRole: 1, carrierRole: 1)
        case .screen:
            // RB leaks to the flat BEHIND the line; wideouts clear the lid.
            return RouteSpec(routes: [
                1: [W(-3.5, 2.5), W(-1.5, 5)],
                7: [W(12, 0)], 8: [W(15, 0)], 9: [W(1.5, 2)],
            ], primaryRole: 1, carrierRole: 1)
        case .dive:
            return RouteSpec(routes: [1: [W(-1, 0.4), W(4, 0.6)]],
                             primaryRole: 1, carrierRole: 1)
        case .jetSweep:
            // Slot flies across in PRE-SNAP motion; the sweep follows him.
            return RouteSpec(routes: [
                1: [W(-1.5, -4.5), W(-0.5, -8.5), W(2, -11), W(8, -12.5)],
                9: [W(-1.2, -9), W(-1.0, -10.5)],
            ], primaryRole: 1, carrierRole: 1, motionRole: 9)
        case .qbSneak:
            return RouteSpec(routes: [0: [W(1.2, 0.3), W(2.5, 0.3)]],
                             primaryRole: 0, carrierRole: 0)

        // --- Short passes ---
        case .slant:
            return RouteSpec(routes: [
                7: [W(3, 0), W(9, -7)],
                8: [W(3, 0), W(9, -7)],
                9: [W(0.5, 4), W(1, 7)],
            ], primaryRole: 7)
        case .quickOut:
            return RouteSpec(routes: [
                8: [W(4.5, 0), W(5, 7)],
                7: [W(4.5, 0), W(5, 7)],
                9: [W(5.5, 0), W(4.5, -0.5)],
            ], primaryRole: 8)
        case .hitch:
            return RouteSpec(routes: [
                7: [W(6.5, 0), W(5, -1)],
                8: [W(6.5, 0), W(5, -1)],
                9: [W(9, -1)],
            ], primaryRole: 7)
        case .flat:
            return RouteSpec(routes: [
                1: [W(-1.5, 4.5), W(0.5, 8), W(1.5, 10)],
                10: [W(5.5, -2), W(7, -3)],
                7: [W(12, 0)],
                8: [W(11, 0), W(10, -5)],
                9: [W(8, -1)],
            ], primaryRole: 1)
        case .drag:
            // Slot shallow across one way, TE dragging back the other.
            return RouteSpec(routes: [
                9: [W(2, -1), W(4.5, -14)],
                10: [W(3, -9)],
                7: [W(15, 0)],
                8: [W(14, 0)],
            ], primaryRole: 9)
        case .stick:
            return RouteSpec(routes: [
                10: [W(6, 0), W(5.5, 2.5)],
                8: [W(4, 0), W(5, 7)],
                9: [W(10, -1)],
                7: [W(12, 0)],
                1: [W(-1.5, 4), W(0, 7)],
            ], primaryRole: 10)
        case .mesh:
            // Two crossers rub at different depths — the X underneath.
            return RouteSpec(routes: [
                9: [W(2, -1), W(5, -16)],
                10: [W(2.5, 0), W(6, -13)],
                7: [W(16, 0)],
                8: [W(11, 0), W(11, -8)],
                1: [W(-1, 4), W(0.5, 7)],
            ], primaryRole: 9)

        // --- Medium passes ---
        case .curl:
            return RouteSpec(routes: [
                7: [W(13, 0), W(10.5, -1.5)],
                8: [W(13, 0), W(10.5, -1.5)],
                9: [W(1, 4), W(2, 7)],
                10: [W(7, -2)],
            ], primaryRole: 7)
        case .dig:
            return RouteSpec(routes: [
                8: [W(14, 0), W(14, -13)],
                7: [W(20, 0)],
                9: [W(3, -1), W(5, -8)],
                1: [W(-1, 4)],
            ], primaryRole: 8)
        case .seam:
            return RouteSpec(routes: [
                10: [W(2.5, -1), W(16, -2)],
                7: [W(18, 0)],
                8: [W(6, 0), W(5, 6)],
                9: [W(11, -1)],
            ], primaryRole: 10)
        case .cross:
            // Deep Cross: the outside WR crosses deep left-to-right while the
            // (right-flipped) slot runs the opposite shallow cross under it.
            return RouteSpec(routes: [
                7: [W(6, 0), W(13, -12), W(17, -28)],
                9: [W(2, -1), W(5.5, -15)],
                8: [W(20, 0)],
                1: [W(-1, 4)],
            ], primaryRole: 7)
        case .postCorner:
            return RouteSpec(routes: [
                9: [W(7, -1), W(11, -5), W(16, 3)],
                7: [W(12, 0), W(12, -10)],
                8: [W(20, 0)],
                10: [W(5, -2)],
            ], primaryRole: 9)
        case .comeback:
            return RouteSpec(routes: [
                8: [W(15, 0), W(12.5, 2.5)],
                7: [W(15, 0), W(12.5, 2.5)],
                9: [W(10, -1)],
            ], primaryRole: 8)
        case .wheel:
            // Back leaks to the flat and turns up the sideline.
            return RouteSpec(routes: [
                1: [W(-2, 5), W(0, 9), W(3, 10.5), W(13, 11)],
                8: [W(7, 0), W(11, -7)],
                9: [W(3, -1), W(5, -10)],
                7: [W(16, 0)],
            ], primaryRole: 1)

        // --- Deep passes ---
        case .goRoute:
            return RouteSpec(routes: [
                7: [W(24, 0.5)],
                8: [W(22, 0)],
                9: [W(4, -1), W(7, -8)],
                10: [W(7, -2)],
            ], primaryRole: 7)
        case .post:
            return RouteSpec(routes: [
                8: [W(11, 0), W(22, -9)],
                7: [W(18, 0)],
                9: [W(1, 4)],
                10: [W(8, -2)],
            ], primaryRole: 8)
        case .corner:
            return RouteSpec(routes: [
                9: [W(9, -1), W(18, 7)],
                8: [W(20, 0)],
                7: [W(11, 0), W(11, -9)],
                1: [W(-1, 4)],
            ], primaryRole: 9)
        case .flood:
            // Three levels to one side: go over out over flat.
            return RouteSpec(routes: [
                8: [W(22, 0)],
                10: [W(7, 0), W(9, 8)],
                1: [W(-1.5, 5), W(0.5, 9.5)],
                9: [W(3, -6)],
                7: [W(16, 0)],
            ], primaryRole: 8)
        case .bomb:
            // Max protect: both backs stay in, verticals take the top off.
            return RouteSpec(routes: [
                7: [W(28, 0.5)],
                8: [W(28, -0.5)],
                9: [W(18, -1)],
            ], primaryRole: 7)
        case .playActionDeep:
            // RB sells the dive (scripted, no route); the shot goes over the top.
            return RouteSpec(routes: [
                7: [W(9, 0), W(22, -11)],
                8: [W(24, 0)],
                9: [W(12, -1)],
            ], primaryRole: 7)

        // ==============================================================
        // Playbook expansion. Same vocabulary as everything above — a
        // waypoint list per role, one gold primary, blockers left out. No
        // new drawing primitive was invented for these: if a concept cannot
        // be said in waypoints it is drawn as the simplest track that is
        // still football (a correct three-point stem beats a decorative
        // squiggle on a 190 pt card).
        // ==============================================================

        // --- Expansion: zone / gap runs ---
        case .insideZone:
            // Press the front side, one cut back, get north.
            return RouteSpec(routes: [1: [W(-1.2, -0.8), W(1.5, -2.2), W(6, -1.6)]],
                             primaryRole: 1, carrierRole: 1)
        case .wideZone:
            // Stretch the whole front, then bend it back off the overrun.
            return RouteSpec(routes: [1: [W(-1.4, 3.5), W(0, 7), W(3.5, 6.5), W(9, 5.5)]],
                             primaryRole: 1, carrierRole: 1)
        case .duo:
            return RouteSpec(routes: [1: [W(-1.0, -0.6), W(2.5, -0.8), W(8, -0.4)]],
                             primaryRole: 1, carrierRole: 1)
        case .power:
            // Open step to the kick-out, then downhill behind the puller;
            // the TE's down block is the only non-carrier track worth art.
            return RouteSpec(routes: [
                1: [W(-1.2, 1.6), W(1.2, -1.8), W(5, -2.4), W(9, -2.0)],
                10: [W(1.0, 2.5)],
            ], primaryRole: 1, carrierRole: 1)
        case .trap:
            return RouteSpec(routes: [1: [W(-0.8, 0.4), W(2, -1.6), W(7, -2.2)]],
                             primaryRole: 1, carrierRole: 1)

        // --- Expansion: QB-conflict runs ---
        case .zoneRead:
            // Both halves of the read are drawn: the give track outside and
            // the QB's pull lane back inside the vacated end.
            return RouteSpec(routes: [
                1: [W(-1.0, 2.5), W(1.0, 4.5)],
                0: [W(-0.8, -0.5), W(1.5, -3.5), W(6, -5.0)],
                9: [W(2, 1)],
            ], primaryRole: 1, carrierRole: 1)
        case .qbDraw:
            // Show the drop, then run it at the middle the rush vacated.
            return RouteSpec(routes: [
                0: [W(-4, 0.5), W(-1, -1), W(4, -1.5), W(9, -1)],
                7: [W(14, 0)], 8: [W(14, 0)],
            ], primaryRole: 0, carrierRole: 0)
        case .endAround:
            // The WR comes back the other way at speed; the back sells flow.
            // `carrierRole: 7` is the X receiver, and the SIM credits him too
            // (`OffensivePlayCall.designedRusher == .receiver` → the same
            // best-WR that `FieldUnit.offense` seats at role 7), so the box
            // score, the feed line and the man carrying the ball agree.
            return RouteSpec(routes: [
                7: [W(-1.5, -12), W(-0.5, -16), W(3, -18), W(9, -19)],
                1: [W(-1.2, 3.5), W(0, 6)],
            ], primaryRole: 7, carrierRole: 7, motionRole: 7)
        case .speedOption:
            // QB attacks the edge with the pitch man running his track.
            return RouteSpec(routes: [
                0: [W(-0.5, 2.5), W(1.5, 5.5), W(4, 7)],
                1: [W(-1.5, 5), W(1, 9)],
            ], primaryRole: 0, carrierRole: 0)

        // --- Expansion: screens ---
        case .bubbleScreen:
            return RouteSpec(routes: [
                9: [W(-0.5, 3.5), W(0, 6)],
                7: [W(1, 1)],
                8: [W(12, 0)],
            ], primaryRole: 9)
        case .tunnelScreen:
            return RouteSpec(routes: [
                8: [W(1, -2), W(1.5, -5)],
                9: [W(0.5, 2)],
                7: [W(12, 0)],
            ], primaryRole: 8)
        case .slipScreen:
            return RouteSpec(routes: [
                1: [W(-2.5, -1.5), W(-0.5, -4)],
                7: [W(13, 0)], 8: [W(13, 0)],
                9: [W(2, 3)],
            ], primaryRole: 1)

        // --- Expansion: short passes ---
        case .spot:
            // Corner / flat / spot-sitter — the triangle on the card.
            return RouteSpec(routes: [
                9: [W(5, -1), W(5.5, -3)],
                10: [W(2, 3.5), W(3, 6.5)],
                8: [W(6, 0), W(9, 5)],
                7: [W(12, 0)],
            ], primaryRole: 9)
        case .snag:
            return RouteSpec(routes: [
                7: [W(4, 0), W(6, -4)],
                9: [W(9, -1), W(13, 4)],
                1: [W(-1, 4), W(0.5, 7)],
                8: [W(14, 0)],
            ], primaryRole: 7)
        case .shallowCross:
            return RouteSpec(routes: [
                9: [W(1.5, -1), W(3, -16)],
                8: [W(12, 0), W(12, -9)],
                7: [W(16, 0)],
                10: [W(6, -2)],
            ], primaryRole: 9)
        case .angle:
            // Back sells the flat, then snaps back under the backer.
            return RouteSpec(routes: [
                1: [W(-1, 3.5), W(1, 6), W(3, 1)],
                10: [W(7, -2)],
                7: [W(13, 0)],
                8: [W(11, 0), W(10, -5)],
            ], primaryRole: 1)
        case .fade:
            return RouteSpec(routes: [
                8: [W(6, 0.5), W(14, 2.5)],
                9: [W(4, -1)],
                7: [W(10, 0), W(9, -1)],
                10: [W(3, 2)],
            ], primaryRole: 8)

        // --- Expansion: medium passes ---
        case .levels:
            return RouteSpec(routes: [
                8: [W(6, 0), W(7, -10)],
                7: [W(12, 0), W(13, -11)],
                9: [W(3, 3)],
                1: [W(-1, 4)],
            ], primaryRole: 7)
        case .yCross:
            // `.crossSet` flips the slot right, so the TE crosser and the
            // slot dig genuinely X the field — the same trick `.cross` uses.
            return RouteSpec(routes: [
                10: [W(4, -2), W(10, -14), W(16, -24)],
                8: [W(20, 0)],
                9: [W(12, -1)],
                7: [W(6, 0), W(5, -1)],
                1: [W(-1.5, 4.5), W(0, 7.5)],
            ], primaryRole: 10)
        case .dagger:
            return RouteSpec(routes: [
                9: [W(16, -1)],
                8: [W(14, 0), W(14, -14)],
                7: [W(20, 0)],
                1: [W(-1, 4)],
            ], primaryRole: 8)
        case .sail:
            return RouteSpec(routes: [
                10: [W(3, 3), W(4, 7)],
                8: [W(12, 0), W(16, 6)],
                9: [W(18, -1)],
                7: [W(14, 0), W(12, -1)],
            ], primaryRole: 8)
        case .smash:
            return RouteSpec(routes: [
                8: [W(5, 0), W(4, 1.5)],
                9: [W(8, -1), W(16, 6)],
                7: [W(14, 0), W(12, 2)],
                10: [W(5, -2)],
            ], primaryRole: 9)

        // --- Expansion: deep passes ---
        case .fourVerts:
            return RouteSpec(routes: [
                7: [W(24, 0)], 8: [W(24, 0)],
                9: [W(22, -2)], 10: [W(20, -3)],
                1: [W(-1, 4)],
            ], primaryRole: 9)
        case .sluggo:
            // Slant-and-go: the stem breaks in, then straightens up the boundary.
            return RouteSpec(routes: [
                8: [W(3, -2.5), W(6, -3.5), W(22, -3)],
                7: [W(16, 0)],
                9: [W(5, -1)],
                10: [W(6, -2)],
            ], primaryRole: 8)
        case .backShoulder:
            return RouteSpec(routes: [
                8: [W(18, 0), W(16, 1.5)],
                7: [W(20, 0)],
                9: [W(6, -1)],
                10: [W(5, 2)],
            ], primaryRole: 8)
        case .hailMary:
            // Depths clamp at the top of the card — four lines running off
            // the edge is exactly the right read.
            return RouteSpec(routes: [
                7: [W(42, 1)], 8: [W(42, -1)],
                9: [W(40, -2)], 10: [W(38, 2)],
            ], primaryRole: 8)

        // --- Expansion: play action ---
        case .paBoot:
            // Role 0 gets the rollout track — that is what makes a boot read
            // as a boot on the card (legal: qbSneak/spike/kneel route 0 too).
            return RouteSpec(routes: [
                0: [W(-3, -1), W(-1.5, 6), W(-1, 9)],
                10: [W(2, 4), W(3, 8)],
                8: [W(12, 0), W(15, 7)],
                9: [W(4, -1), W(6, -14)],
                7: [W(18, 0)],
            ], primaryRole: 8)
        case .paCross:
            return RouteSpec(routes: [
                7: [W(8, 0), W(14, -13), W(19, -26)],
                9: [W(3, -1), W(6, -12)],
                8: [W(22, 0)],
                10: [W(6, 3)],
            ], primaryRole: 7)
        case .paGlance:
            return RouteSpec(routes: [
                8: [W(3, 0), W(9, -6)],
                7: [W(3, 0), W(9, -6)],
                9: [W(5, -1)],
                10: [W(4, 2)],
            ], primaryRole: 8)

        // --- Expansion: RPO ---
        // Every RPO draws the give track for role 1 so the card shows the
        // mesh point; the back's track stays short because the pass
        // resolution makes it a fake.
        case .rpoBubble:
            return RouteSpec(routes: [
                9: [W(-0.5, 3.5), W(0, 6)],
                1: [W(-1, -1), W(2, -2)],
                7: [W(1, 1)],
                8: [W(11, 0)],
            ], primaryRole: 9)
        case .rpoSlant:
            return RouteSpec(routes: [
                8: [W(2.5, 0), W(8, -6)],
                1: [W(-1, -1), W(2, -2)],
                9: [W(1, 2)],
                7: [W(11, 0)],
            ], primaryRole: 8)
        case .rpoStick:
            return RouteSpec(routes: [
                10: [W(5.5, 0), W(5, 2.5)],
                9: [W(2, 3.5)],
                1: [W(-1, -1), W(2, -2)],
                8: [W(12, 0)],
            ], primaryRole: 10)
        case .rpoPop:
            return RouteSpec(routes: [
                9: [W(3, -1), W(10, -2)],
                1: [W(-1, -1), W(2, -2)],
                8: [W(12, 0)], 7: [W(12, 0)],
            ], primaryRole: 9)

        // --- Expansion: special ---
        case .tushPush:
            return RouteSpec(routes: [
                0: [W(1.0, 0), W(2.0, 0)],
                1: [W(-0.4, 0)],
            ], primaryRole: 0, carrierRole: 0)

        // --- Clock plays (card art only — their scripts are bespoke) ---
        case .spike:
            return RouteSpec(routes: [0: [W(-7, 0)]], primaryRole: 0, carrierRole: 0)
        case .kneel:
            return RouteSpec(routes: [0: [W(-4, 0)]], primaryRole: 0, carrierRole: 0)
        }
    }

    // MARK: - Play Shape (how the call is EXECUTED)
    //
    // `routes` says where the skill players go. `Shape` says what everybody
    // ELSE does with the same call: how the front blocks it, what the QB does
    // with the ball, how long he holds it. Both are data — the choreographer
    // reads them, it never switches on a play by name.

    /// How the offensive line works a run concept.
    enum RunScheme {
        /// Not a run.
        case none
        /// Zone: the whole front slides in the carrier's flow and reaches.
        case zone
        /// Gap: down blocks with a puller wrapping to the point of attack.
        case gap
        /// Man/down blocking: everybody covers his own man, straight ahead.
        case manDown
        /// Everybody surges forward as one body (sneak / push).
        case surge
    }

    /// What the QB does after the exchange.
    enum QBAction {
        /// Straight-back drop to a launch point.
        case dropback
        /// Designed rollout — the spec draws HIS track (boot / sprint out).
        case rollout
        /// Hand the ball off at the mesh.
        case handoff
        /// Pitch it out.
        case pitch
        /// He keeps it (sneak, draw, option, scramble).
        case keeper
        /// Ride the mesh, then pull it and throw NOW.
        case rpoRide
    }

    /// Everything the choreographer needs about a call beyond its routes.
    struct Shape {
        var run: RunScheme = .none
        /// A gap scheme's backside guard wraps to the point of attack.
        var pulls = false
        /// Drop depth in STEPS (0 = the ball is out now, 3/5/7 = real drops).
        var dropSteps: Int = 5
        var qb: QBAction = .dropback
        /// The box gets a run fake before the drop.
        var playAction = false
        /// Run-fake-then-throw: the ride is real, the release is instant.
        var rpo = false
        /// A slow screen: invite the rush, leak the line out in front.
        var slowScreen = false
    }

    /// The shape of one call. Everything is read from properties the call
    /// already publishes (`isRun`, `simulatorHint.passDepth`,
    /// `simulatorHint.isPlayAction`, `formationFamily`, and the spec's own
    /// `carrierRole` / role-0 track); the only bespoke table is the four-way
    /// run-scheme grouping, which no other type can infer.
    static func shape(for call: OffensivePlayCall?) -> Shape {
        var shape = Shape()
        guard let call else { return shape }
        let spec = RouteSpec.spec(for: call)
        let hint = call.simulatorHint
        shape.playAction = hint.isPlayAction
        shape.rpo = call.category == "RPO"

        // The legacy wart: `.screen` reports `isRun` but is thrown. Every
        // screen is a pass on the field, so the category decides here.
        let isScreen = call.category == "Screen"
        if call.isRun && !isScreen {
            shape.run = runScheme(for: call)
            shape.pulls = [.power, .counter, .trap].contains(call)
            shape.dropSteps = 0
            // The spec already says who ends up with it: a role-0 carrier is a
            // keeper, a toss is a pitch, everything else is a mesh hand-off.
            if call == .toss {
                shape.qb = .pitch
            } else if spec.carrierRole == 0 {
                shape.qb = .keeper
            } else {
                shape.qb = .handoff
            }
            // A draw sells the drop first, so it still needs drop depth.
            if call == .draw || call == .qbDraw { shape.dropSteps = 3 }
            return shape
        }

        shape.slowScreen = call == .screen || call == .slipScreen
        switch hint.passDepth {
        case .short: shape.dropSteps = 3
        case .medium: shape.dropSteps = 5
        case .deep: shape.dropSteps = 7
        case nil: shape.dropSteps = 5
        }
        // The ball is out on rhythm: quick screens and RPOs never really drop.
        if shape.rpo || isScreen { shape.dropSteps = 0 }
        if shape.rpo {
            shape.qb = .rpoRide
        } else if spec.routes[0] != nil {
            // The design draws the passer a track — that IS the boot/sprint-out.
            shape.qb = .rollout
        } else {
            shape.qb = .dropback
        }
        return shape
    }

    /// The four blocking families. Zone reaches and flows, gap pulls and
    /// wraps, man/down blocking fires straight off the ball, and a surge is
    /// eleven men pushing one pile.
    private static func runScheme(for call: OffensivePlayCall) -> RunScheme {
        switch call {
        case .insideZone, .wideZone, .outsideRun, .toss, .draw,
             .zoneRead, .qbDraw, .jetSweep, .endAround, .speedOption, .screen:
            return .zone
        case .power, .counter, .trap:
            return .gap
        case .qbSneak, .tushPush:
            return .surge
        default:
            return .manDown
        }
    }

    /// Generic spread concept for snaps with no dialed call (AI drives):
    /// depth-tiered so the field still shows a believable pattern.
    static func generic(forDepth depth: Float) -> RouteSpec {
        typealias W = Waypoint
        if depth < 8 {
            return RouteSpec(routes: [
                9: [W(2, -1), W(5, -8)],
                7: [W(3, 0), W(9, -7)],
                8: [W(4.5, 0), W(5, 7)],
                10: [W(5, 0), W(4.5, 2)],
                1: [W(-1, 4), W(0, 7)],
            ], primaryRole: 9)
        }
        if depth < 18 {
            return RouteSpec(routes: [
                7: [W(13, 0), W(11, -2)],
                8: [W(14, 0), W(14, -12)],
                9: [W(2, -1), W(5, -10)],
                10: [W(8, -2)],
                1: [W(-1, 4)],
            ], primaryRole: 7)
        }
        return RouteSpec(routes: [
            8: [W(22, 0)],
            7: [W(20, 0)],
            9: [W(14, -2)],
            10: [W(7, -2)],
            1: [W(-1, 4)],
        ], primaryRole: 8)
    }

    /// Safety-valve route when the sim targets a role the spec has blocking
    /// (checkdowns happen): a swing for the back, a settle for everyone else.
    static func checkdown(role: Int) -> [Waypoint] {
        typealias W = Waypoint
        switch role {
        case 1:  return [W(-1, 4), W(0.5, 7)]
        case 9:  return [W(4, -1)]
        case 10: return [W(4, -1)]
        default: return [W(6, 0), W(5, -1)]
        }
    }
}

// MARK: - Play Card Projection

/// 2D projection of a play's spec for the X&O card: alignment spots and
/// route polylines in normalized space (offense drives toward the top, LOS
/// at `losY`). Built from the SAME spec + formation function the 3D field
/// runs, so the chalkboard card cannot diverge from the field.
struct PlayDiagramData {
    struct Line {
        let points: [CGPoint]
        let primary: Bool
    }

    let losY: CGFloat
    let linemen: [CGPoint]
    let qb: CGPoint
    let skill: [CGPoint]
    let routes: [Line]
}

extension RouteSpec {
    static func diagram(for call: OffensivePlayCall, mirror: Float = 1) -> PlayDiagramData {
        let losY: CGFloat = 0.60
        let playType: PlayType = call == .kneel ? .kneel : (call.isRun ? .run : .pass)
        let formation = PlayChoreographer.offensePositions(for: playType, call: call,
                                                           losZ: 0, direction: 1, mirror: mirror)
        let spec = RouteSpec.spec(for: call)

        // Downfield yards compress a touch more than backfield yards so the
        // gun/under-center looks stay readable on a card.
        func norm(_ x: Float, _ z: Float) -> CGPoint {
            let nx = 0.5 + CGFloat(x) / 52
            let ny = z >= 0 ? losY - CGFloat(z) * 0.0195 : losY - CGFloat(z) * 0.032
            return CGPoint(x: min(max(nx, 0.03), 0.97), y: min(max(ny, 0.04), 0.96))
        }

        let linemen = (2...6).map { norm(formation[$0].x, formation[$0].z) }
        let qb = norm(formation[0].x, formation[0].z)
        let skill = [1, 7, 8, 9, 10].map { norm(formation[$0].x, formation[$0].z) }

        var routes: [PlayDiagramData.Line] = []
        for (role, _) in spec.routes.sorted(by: { $0.key < $1.key }) {
            guard role < formation.count,
                  let pts = spec.points(role: role, startX: formation[role].x,
                                        startZ: formation[role].z, losZ: 0, direction: 1,
                                        mirror: mirror)
            else { continue }
            routes.append(PlayDiagramData.Line(points: pts.map { norm($0.x, $0.z) },
                                               primary: role == spec.primaryRole))
        }
        return PlayDiagramData(losY: losY, linemen: linemen, qb: qb, skill: skill, routes: routes)
    }
}

// MARK: - Route Path (arc-length parameterized polyline)

/// A field-space polyline with cumulative arc length, so a runner can cover
/// it at constant speed across sequential play steps and the choreographer
/// can find "the point on the route nearest the simulated depth".
struct RoutePath {
    let pts: [(x: Float, z: Float)]
    let cum: [Float]
    let total: Float

    init(points: [(x: Float, z: Float)]) {
        var cleaned = points
        if cleaned.isEmpty { cleaned = [(0, 0)] }
        var cumulative: [Float] = [0]
        var running: Float = 0
        for index in 1..<max(cleaned.count, 1) {
            let dx = cleaned[index].x - cleaned[index - 1].x
            let dz = cleaned[index].z - cleaned[index - 1].z
            running += (dx * dx + dz * dz).squareRoot()
            cumulative.append(running)
        }
        pts = cleaned
        cum = cumulative
        total = max(running, 0.001)
    }

    var end: (x: Float, z: Float) { pts[pts.count - 1] }

    /// Position at a 0…1 arc-length fraction.
    func point(at fraction: Float) -> (x: Float, z: Float) {
        let target = min(max(fraction, 0), 1) * total
        for index in 1..<pts.count where cum[index] >= target {
            let segment = cum[index] - cum[index - 1]
            let t = segment > 0.0001 ? (target - cum[index - 1]) / segment : 1
            return (pts[index - 1].x + (pts[index].x - pts[index - 1].x) * t,
                    pts[index - 1].z + (pts[index].z - pts[index - 1].z) * t)
        }
        return end
    }

    /// Movement targets between two fractions: every interior waypoint plus
    /// the end position, EXCLUDING the start position (the runner is there).
    func slice(from: Float, to: Float) -> [(x: Float, z: Float)] {
        let lo = min(max(from, 0), 1) * total
        let hi = min(max(to, 0), 1) * total
        guard hi - lo > 0.02 else { return [] }
        var out: [(x: Float, z: Float)] = []
        for index in 1..<pts.count where cum[index] > lo + 0.01 && cum[index] < hi - 0.01 {
            out.append(pts[index])
        }
        out.append(point(at: to))
        return out
    }

    /// The path truncated at a fraction (start point kept).
    func prefix(to fraction: Float) -> RoutePath {
        RoutePath(points: [pts[0]] + slice(from: 0, to: fraction))
    }

    /// Arc-length fraction of the point nearest to world `z` — ties prefer
    /// the LATER point, so comeback/curl breaks resolve to the break, not
    /// the stem passing the same depth.
    func fractionNearest(z: Float) -> Float {
        var bestFraction: Float = 1
        var bestError = Float.greatestFiniteMagnitude
        for index in 1..<pts.count {
            let a = pts[index - 1], b = pts[index]
            let candidateT: Float
            if abs(b.z - a.z) > 0.0001 {
                candidateT = min(max((z - a.z) / (b.z - a.z), 0), 1)
            } else {
                candidateT = 1
            }
            let candidateZ = a.z + (b.z - a.z) * candidateT
            let error = abs(candidateZ - z)
            let distance = cum[index - 1] + (cum[index] - cum[index - 1]) * candidateT
            let fraction = distance / total
            if error < bestError - 0.01 || (error < bestError + 0.01 && fraction > bestFraction) {
                bestError = error
                bestFraction = fraction
            }
        }
        return bestFraction
    }

    /// Deepest point past the LOS along the path, in yards downfield.
    func maxDepth(losZ: Float, direction: Float) -> Float {
        pts.map { ($0.z - losZ) * direction }.max() ?? 0
    }
}
