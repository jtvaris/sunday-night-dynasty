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
    static func resolve(_ waypoints: [Waypoint], startX: Float, startZ: Float,
                        losZ: Float, direction: Float,
                        depthScale: Float = 1) -> [(x: Float, z: Float)] {
        // Which sideline is "his": alignment left of the ball mirrors laterals.
        let sideSign: Float = startX < -0.5 ? -1 : 1
        var points: [(x: Float, z: Float)] = [(startX, startZ)]
        for waypoint in waypoints {
            points.append((startX + waypoint.lateral * sideSign,
                           losZ + direction * waypoint.depth * depthScale))
        }
        return points
    }

    /// Field-space polyline for one role (alignment start included), or nil
    /// when the role blocks on this play.
    func points(role: Int, startX: Float, startZ: Float, losZ: Float,
                direction: Float, depthScale: Float = 1) -> [(x: Float, z: Float)]? {
        guard let waypoints = routes[role] else { return nil }
        return RouteSpec.resolve(waypoints, startX: startX, startZ: startZ,
                                 losZ: losZ, direction: direction, depthScale: depthScale)
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

        // --- Clock plays (card art only — their scripts are bespoke) ---
        case .spike:
            return RouteSpec(routes: [0: [W(-7, 0)]], primaryRole: 0, carrierRole: 0)
        case .kneel:
            return RouteSpec(routes: [0: [W(-4, 0)]], primaryRole: 0, carrierRole: 0)
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
    static func diagram(for call: OffensivePlayCall) -> PlayDiagramData {
        let losY: CGFloat = 0.60
        let playType: PlayType = call == .kneel ? .kneel : (call.isRun ? .run : .pass)
        let formation = PlayChoreographer.offensePositions(for: playType, call: call,
                                                           losZ: 0, direction: 1)
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
                                        startZ: formation[role].z, losZ: 0, direction: 1)
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
