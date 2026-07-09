import SceneKit

// MARK: - Play Choreographer

/// Pure choreography builder for the 3D coached-game view.
/// Converts a `PlayResult` into pre-snap formation arrays and a sequential list
/// of `FootballFieldScene.PlayStep`s — no SceneKit rendering here, only
/// geometry math and step construction.
///
/// World-coordinate contract (matches `FootballFieldScene`):
/// - X = sideline to sideline, Z = end zone to end zone, 1 unit = 1 yard,
///   origin at midfield. Playing field spans z ∈ [-50, 50], end zones to ±60.
/// - The offense drives toward +Z when it is the HOME team, toward -Z otherwise.
/// - `yardLine` is 0-100 measured from the OFFENSE's own goal line, so
///   LOS worldZ = offenseIsHome ? yardLine - 50 : 50 - yardLine and
///   direction = offenseIsHome ? +1 : -1.
///
/// Node index contract (used by every step):
/// - Home players occupy scene node indexes 0-10, away players 11-21.
/// - OFFENSE role order: 0=QB, 1=RB, 2-6=OL (LT,LG,C,RG,RT),
///   7=WR left (wide), 8=WR right (wide), 9=slot WR, 10=TE.
/// - DEFENSE role order: 0-3=DL, 4-6=LB, 7-8=CB, 9-10=S.
/// - `formation(for:losZ:direction:)` returns home/away arrays already ordered
///   this way, so passing them straight to `positionPlayers` /
///   `movePlayersToFormation` keeps the role → nodeIndex mapping stable for
///   the steps built here.
struct PlayChoreographer {

    private typealias Step = FootballFieldScene.PlayStep
    private typealias Move = (nodeIndex: Int, to: SCNVector3, duration: TimeInterval)

    // MARK: - Constants

    /// All target positions are clamped inside these field bounds.
    private enum Bounds {
        static let minX: Float = -25
        static let maxX: Float = 25
        static let minZ: Float = -58
        static let maxZ: Float = 58
    }

    private static let playerY: Float = 0.5      // capsule center height
    private static let ballGroundY: Float = 0.3  // ball resting on the turf
    private static let ballCarryY: Float = 0.9   // ball at chest height

    // MARK: - Coordinate Mapping

    /// World Z of the line of scrimmage for a 0-100 yard line measured from
    /// the offense's own goal line.
    static func losZ(yardLine: Int, offenseIsHome: Bool) -> Float {
        offenseIsHome ? Float(yardLine) - 50 : 50 - Float(yardLine)
    }

    // MARK: - Formations

    /// Builds the pre-snap formation for both teams.
    /// `direction` = +1 when the offense is the home team (drives toward +Z),
    /// -1 otherwise — it also decides which side of the tuple gets the offense.
    /// Optional role-ordered jersey numbers replace the placeholder digits so
    /// the field shows the real starters.
    static func formation(for playType: PlayType, call: OffensivePlayCall? = nil,
                          defensivePackage: DefensivePackage? = nil,
                          losZ: Float, direction: Float,
                          offenseNumbers: [Int]? = nil, defenseNumbers: [Int]? = nil)
        -> (home: [(x: Float, z: Float, number: Int)], away: [(x: Float, z: Float, number: Int)]) {
        var offense = offensePositions(for: playType, call: call, losZ: losZ, direction: direction)
        var defense = defensePositions(losZ: losZ, direction: direction, package: defensivePackage)
        offense = renumber(offense, with: offenseNumbers)
        defense = renumber(defense, with: defenseNumbers)
        return direction > 0 ? (home: offense, away: defense) : (home: defense, away: offense)
    }

    private static func renumber(_ positions: [(x: Float, z: Float, number: Int)],
                                 with numbers: [Int]?) -> [(x: Float, z: Float, number: Int)] {
        guard let numbers, numbers.count == positions.count else { return positions }
        return zip(positions, numbers).map { (x: $0.x, z: $0.z, number: $1) }
    }

    /// Position-appropriate pre-snap stances keyed by per-team node index:
    /// OL/DL/TE dig into a deep 3-point with the hand down, RB/LB/S sit in a
    /// 2-point crouch with hands near the knees, WR/CB stand in an upright
    /// split stance. The QB stays tall (upright by omission).
    static func stances(offenseIsHome: Bool)
        -> (home: [Int: FootballFieldScene.Stance], away: [Int: FootballFieldScene.Stance]) {
        var offense: [Int: FootballFieldScene.Stance] = [1: .twoPoint, 10: .threePoint]
        for role in 2...6 { offense[role] = .threePoint }   // OL
        for role in [7, 8, 9] { offense[role] = .split }    // WRs
        var defense: [Int: FootballFieldScene.Stance] = [:]
        for role in 0...3 { defense[role] = .threePoint }   // DL
        for role in [4, 5, 6, 9, 10] { defense[role] = .twoPoint }  // LBs + safeties
        for role in [7, 8] { defense[role] = .split }       // CBs
        return offenseIsHome ? (home: offense, away: defense) : (home: defense, away: offense)
    }

    /// Formation arrays for the pre-snap lineup of `play`. The view passes
    /// these to `movePlayersToFormation(home:away:duration:)`; the
    /// choreographer only supplies the geometry.
    static func preSnapStep(for play: PlayResult, losYardLine: Int, offenseIsHome: Bool,
                            call: OffensivePlayCall? = nil,
                            defensivePackage: DefensivePackage? = nil,
                            offenseNumbers: [Int]? = nil, defenseNumbers: [Int]? = nil)
        -> (home: [(x: Float, z: Float, number: Int)], away: [(x: Float, z: Float, number: Int)]) {
        formation(
            for: play.playType,
            call: call,
            defensivePackage: defensivePackage,
            losZ: losZ(yardLine: losYardLine, offenseIsHome: offenseIsHome),
            direction: offenseIsHome ? 1 : -1,
            offenseNumbers: offenseNumbers,
            defenseNumbers: defenseNumbers
        )
    }

    /// Offense role order: 0=QB, 1=RB, 2-6=OL, 7=WR left, 8=WR right, 9=slot, 10=TE.
    /// The alignment reflects the CALL: under-center I-form for interior runs,
    /// compressed splits for the ground game, spread shotgun for deep shots.
    private static func offensePositions(for playType: PlayType, call: OffensivePlayCall? = nil,
                                          losZ: Float, direction: Float)
        -> [(x: Float, z: Float, number: Int)] {
        let behind = losZ - direction * 0.7  // OL just behind the LOS

        // Alignment parameters per call family.
        var qbDepth: Float = 5        // shotgun
        var rb: (x: Float, depth: Float) = (1.8, 5)   // beside the QB
        var wrSplit: Float = 15
        var slot: (x: Float, depth: Float) = (-8, 1.5)
        var teX: Float = 5

        switch playType {
        case .punt:      qbDepth = 7; rb = (1.5, 6)
        case .fieldGoal, .extraPoint: qbDepth = 3; rb = (1.5, 3)
        case .kneel:     qbDepth = 1.2; rb = (0, 4.5); wrSplit = 6; slot = (-4, 1.2); teX = 4
        default:
            switch call {
            case .insideRun, .qbSneak, .dive:
                // I-formation: QB under center, back deep downhill, tight splits.
                qbDepth = 1.2; rb = (0, 5.5); wrSplit = 12; slot = (-7, 1.2); teX = 4.2
            case .outsideRun, .jetSweep:
                qbDepth = 4.5; rb = (-2.5, 5.2); wrSplit = 14; slot = (-8, 1.3)
            case .draw, .screen:
                qbDepth = 5.5; rb = (1.8, 5.5)
            case .slant, .quickOut, .flat, .drag, .stick, .mesh:
                qbDepth = 4; wrSplit = 15; slot = (-9, 1.3)
            case .goRoute, .post, .corner, .bomb, .playActionDeep:
                // Spread: maximum width, everyone in the pattern.
                qbDepth = 5.5; wrSplit = 17; slot = (-11, 1.4)
            default:
                break
            }
        }

        let qbZ = losZ - direction * qbDepth
        let raw: [(x: Float, z: Float, number: Int)] = [
            (0, qbZ, 12),                                        // 0 QB
            (rb.x, losZ - direction * rb.depth, 28),             // 1 RB
            (-3, behind, 71),                                    // 2 LT
            (-1.5, behind, 66),                                  // 3 LG
            (0, behind, 55),                                     // 4 C
            (1.5, behind, 64),                                   // 5 RG
            (3, behind, 75),                                     // 6 RT
            (-wrSplit, losZ - direction * 1.2, 81),              // 7 WR left (wide)
            (wrSplit, losZ - direction * 1.2, 88),               // 8 WR right (wide)
            (slot.x, losZ - direction * slot.depth, 84),         // 9 slot WR
            (teX, behind, 87),                                   // 10 TE
        ]
        return raw.map { (x: clampX($0.x), z: clampZ($0.z), number: $0.number) }
    }

    /// Defense role order: 0-3=DL, 4-6=LB, 7-8=CB, 9-10=S.
    /// The alignment shows the CALL: nickel walks a backer over the slot,
    /// press man puts the corners on the line, blitzes creep the box, goal
    /// line squeezes everyone tight.
    private static func defensePositions(losZ: Float, direction: Float,
                                         package: DefensivePackage? = nil)
        -> [(x: Float, z: Float, number: Int)] {
        // Front seven baseline.
        var dlXs: [Float] = [-4.5, -1.5, 1.5, 4.5]
        var dlDepth: Float = 1
        var lbSpots: [(x: Float, depth: Float)] = [(-5, 5), (0, 5), (5, 5)]
        // Secondary baseline (cover 3 shell).
        var cbDepth: Float = 7
        var cbSplit: Float = 15
        var sSpots: [(x: Float, depth: Float)] = [(-6, 12), (6, 12)]

        switch package?.front {
        case .nickel:
            // LB-R walks out over the slot.
            lbSpots = [(-3.5, 4.5), (1.5, 4.5), (-9, 2.5)]
        case .dime:
            // Two backers out in coverage, one in the middle.
            lbSpots = [(8, 5.5), (0, 4.5), (-9, 3)]
        case .bear:
            // 46 look: DL squeezed tight, backers stacked right behind them.
            dlXs = [-3.6, -1.2, 1.2, 3.6]
            dlDepth = 0.9
            lbSpots = [(-5.5, 2.4), (0, 3.2), (5.5, 2.4)]
            sSpots = [(-6, 11), (6, 7)]
        case .goalLine:
            dlXs = [-3.2, -1.1, 1.1, 3.2]
            dlDepth = 0.8
            lbSpots = [(-3, 2.4), (0, 2.2), (3, 2.4)]
            sSpots = [(-5, 6), (5, 6)]
            cbDepth = 3
        default:
            break
        }

        switch package?.coverage {
        case .manToMan:
            // Press: corners up in the receivers' faces.
            cbDepth = min(cbDepth, 1.6)
            if package?.front != .goalLine { sSpots = [(-6, 10), (6, 10)] }
        case .cover1:
            // Man free: tight corners, single-high safety, the other one down.
            cbDepth = min(cbDepth, 2.5)
            if package?.front != .goalLine, package?.front != .bear {
                sSpots = [(0, 14), (6, 6)]
            }
        case .cover2:
            cbDepth = min(cbDepth, 5)
            sSpots = [(-9, 13), (9, 13)]
        case .cover4:
            cbDepth = max(cbDepth, 8)
            sSpots = [(-7, 13), (7, 13)]
        case .prevent:
            // Everyone bails: corners give a huge cushion, safeties sky-deep.
            cbDepth = max(cbDepth, 10)
            sSpots = [(-8, 16), (8, 16)]
        default:
            break
        }

        // Blitz looks: creep the rushers toward the line pre-snap.
        switch package?.blitz {
        case .lbBlitz:
            lbSpots = lbSpots.map { (x: $0.x * 0.7, depth: min($0.depth, 2.6)) }
        case .doubleAGap:
            // Both backers mug the A-gaps right over the center.
            lbSpots = [(-1.2, 1.8), (1.2, 1.8), (5, 4.5)]
        case .safetyBlitz:
            sSpots[1] = (5, 2.5)   // S-R creeps down off the edge
        case .dbBlitz:
            sSpots[1] = (7, 2.8)   // S-R shows off the edge
        case .allOutBlitz:
            lbSpots = lbSpots.map { (x: $0.x * 0.6, depth: 2.2) }
            sSpots[1] = (6.5, 2.6)
        default:
            break
        }

        let raw: [(x: Float, z: Float, number: Int)] = [
            (dlXs[0], losZ + direction * dlDepth, 94),   // 0 DE left
            (dlXs[1], losZ + direction * dlDepth, 90),   // 1 DT
            (dlXs[2], losZ + direction * dlDepth, 93),   // 2 DT
            (dlXs[3], losZ + direction * dlDepth, 97),   // 3 DE right
            (lbSpots[0].x, losZ + direction * lbSpots[0].depth, 54),  // 4 LB left
            (lbSpots[1].x, losZ + direction * lbSpots[1].depth, 52),  // 5 MLB
            (lbSpots[2].x, losZ + direction * lbSpots[2].depth, 56),  // 6 LB right
            (-cbSplit, losZ + direction * cbDepth, 21),  // 7 CB left
            (cbSplit, losZ + direction * cbDepth, 24),   // 8 CB right
            (sSpots[0].x, losZ + direction * sSpots[0].depth, 31),    // 9 S left
            (sSpots[1].x, losZ + direction * sSpots[1].depth, 33),    // 10 S right
        ]
        return raw.map { (x: clampX($0.x), z: clampZ($0.z), number: $0.number) }
    }

    // MARK: - Play Steps

    /// Builds the full animation timeline for a simulated play.
    /// Total runtime stays roughly in the 3.5-6s range for scrimmage plays
    /// (kneel/spike/kicks intentionally shorter).
    static func steps(for play: PlayResult, losYardLine: Int, offenseIsHome: Bool,
                      matchups: PlayMatchups? = nil,
                      call: OffensivePlayCall? = nil,
                      defensivePackage: DefensivePackage? = nil)
        -> [FootballFieldScene.PlayStep] {
        let context = Context(play: play, losYardLine: losYardLine, offenseIsHome: offenseIsHome,
                              matchups: matchups, call: call, defensivePackage: defensivePackage)
        let gainZ = clampZ(context.losZ + context.direction * Float(play.yardsGained))

        switch play.outcome {
        case .rush:
            return rushSteps(context, endZ: gainZ).steps
        case .kneel:
            return kneelSteps(context)
        case .completion:
            let endZ = clampZ(context.losZ + context.direction * Float(max(play.yardsGained, 1)))
            return completionSteps(context, endZ: endZ).steps
        case .incompletion, .twoPointFailed:
            // A stuffed two-point RUN try is swallowed short of the line —
            // only pass tries (and real incompletions) show the throw.
            if play.outcome == .twoPointFailed, call?.isRun == true {
                return rushSteps(context,
                                 endZ: clampZ(context.losZ + context.direction * 1)).steps
            }
            return incompletionSteps(context)
        case .sack:
            return sackSteps(context)
        case .interception:
            return interceptionSteps(context)
        case .fumble, .fumbleLost:
            return fumbleSteps(context, endZ: gainZ)
        case .touchdown, .twoPointGood:
            return touchdownSteps(context)
        case .punt, .touchback:
            return puntSteps(context)
        case .fieldGoalGood, .extraPointGood:
            return fieldGoalSteps(context, good: true)
        case .fieldGoalMissed, .extraPointMissed:
            return fieldGoalSteps(context, good: false)
        case .safety:
            // Carrier is swallowed behind his own goal line.
            return rushSteps(context, endZ: clampZ(-context.direction * 51.5)).steps
        case .spike:
            return spikeSteps(context)
        case .penalty:
            return defaultSteps(context)
        }
    }

    // MARK: - Script Context

    /// Precomputed geometry + node index mapping for one play.
    private struct Context {
        let play: PlayResult
        let losZ: Float
        let direction: Float
        /// First scene node index of the offense (0 when home, 11 when away).
        let oBase: Int
        /// First scene node index of the defense.
        let dBase: Int
        /// Pre-snap positions in role order (already clamped).
        let offense: [(x: Float, z: Float, number: Int)]
        let defense: [(x: Float, z: Float, number: Int)]
        /// Individual battle results shaping the visuals (nil = neutral).
        let matchups: PlayMatchups?
        /// The coach's called play, when one was dialed (shapes 2-pt scripts).
        let call: OffensivePlayCall?

        init(play: PlayResult, losYardLine: Int, offenseIsHome: Bool,
             matchups: PlayMatchups? = nil,
             call: OffensivePlayCall? = nil,
             defensivePackage: DefensivePackage? = nil) {
            self.play = play
            self.losZ = PlayChoreographer.losZ(yardLine: losYardLine, offenseIsHome: offenseIsHome)
            self.direction = offenseIsHome ? 1 : -1
            self.oBase = offenseIsHome ? 0 : 11
            self.dBase = offenseIsHome ? 11 : 0
            self.offense = PlayChoreographer.offensePositions(for: play.playType, call: call,
                                                              losZ: losZ, direction: direction)
            self.defense = PlayChoreographer.defensePositions(losZ: losZ, direction: direction,
                                                              package: defensivePackage)
            self.matchups = matchups
            self.call = call
        }

        /// Yards of receiver separation at the catch (visual).
        var separation: Float { Float(matchups?.separation ?? 1.5) }
        /// 0 stuffed … 1 gaping hole (visual).
        var holeSize: Float { Float(matchups?.holeSize ?? 0.5) }
        /// How fast the pocket dies, 0…1.
        var pocketCollapse: Float { Float(matchups?.pocketCollapse ?? 0.4) }
        /// Ball-carrier/target offense role when the sim named one.
        var carrierRole: Int? { matchups?.targetOffRole }
        /// The defender credited with a defense-won battle, if any.
        var defenseWinnerRole: Int? {
            matchups?.events.first(where: { !$0.offenseWon && $0.defRole != nil })?.defRole
        }

        // Offense node indexes
        var qb: Int { oBase }
        var rb: Int { oBase + 1 }
        var wrLeft: Int { oBase + 7 }
        var wrRight: Int { oBase + 8 }
        var slot: Int { oBase + 9 }

        // Defense node indexes
        func dl(_ role: Int) -> Int { dBase + role }          // role 0-3
        func lb(_ role: Int) -> Int { dBase + 4 + role }      // role 0-2
        func cb(_ role: Int) -> Int { dBase + 7 + role }      // role 0-1
        func safety(_ role: Int) -> Int { dBase + 9 + role }  // role 0-1

        /// Pre-snap world position of an offense role (0-10).
        func offenseStart(_ role: Int) -> SCNVector3 {
            let info = offense[role]
            return SCNVector3(info.x, PlayChoreographer.playerY, info.z)
        }
    }

    // MARK: - All-22 Support Movement
    //
    // Every script layers these on top of its scripted key actors so all 22
    // players do something on every snap. Each helper lerps from the pre-snap
    // spot toward a play-long destination; calling it with a growing `p`
    // across successive steps keeps each player moving along one continuous
    // path (steps are sequential, so the next target simply extends the last).

    /// Deterministic per-lineman lateral offsets so the trenches don't move in lockstep.
    private static let jitters: [Float] = [-0.35, 0.3, -0.15, 0.4, 0.1]

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    /// Scripted moves win: support moves for the same node are dropped.
    private static func merge(_ scripted: [Move], _ support: [Move]) -> [Move] {
        let taken = Set(scripted.map(\.nodeIndex))
        return scripted + support.filter { !taken.contains($0.nodeIndex) }
    }

    /// Run blocking: the OL fires off the ball and the DL meets it at the LOS.
    /// `dlShift` > 0 pushes the DL backward off the ball (the line is winning);
    /// < 0 lets it penetrate into the backfield (the front got beat).
    private static func lineSurgeMoves(_ c: Context, p: Float, d: TimeInterval,
                                       dlShift: Float = 0) -> [Move] {
        var moves: [Move] = []
        for i in 0..<5 {
            let start = c.offense[2 + i]
            moves.append((c.oBase + 2 + i,
                          player(start.x + jitters[i] * p,
                                 lerp(start.z, c.losZ + c.direction * (0.25 + max(0, dlShift) * 0.6), p)), d))
        }
        for i in 0..<4 {
            let start = c.defense[i]
            moves.append((c.dl(i),
                          player(start.x - jitters[i] * 0.5 * p,
                                 lerp(start.z, c.losZ + c.direction * (0.7 + dlShift), p)), d))
        }
        return moves
    }

    /// Pass protection: the OL sets a pocket (tackles deeper than the interior)
    /// while the DL rushes — edges loop wide, tackles push the middle.
    private static func pocketMoves(_ c: Context, p: Float, d: TimeInterval) -> [Move] {
        var moves: [Move] = []
        for i in 0..<5 {
            let start = c.offense[2 + i]
            let depth: Float = (i == 0 || i == 4) ? 1.9 : 1.2
            let widen = Float(i - 2) * 0.35
            moves.append((c.oBase + 2 + i,
                          player(start.x + widen * p,
                                 lerp(start.z, c.losZ - c.direction * depth, p)), d))
        }
        for i in 0..<4 {
            let start = c.defense[i]
            let wide: Float = i == 0 ? -1.2 : (i == 3 ? 1.2 : 0)
            moves.append((c.dl(i),
                          player(start.x + wide * p,
                                 lerp(start.z, c.losZ - c.direction * 1.6, p)), d))
        }
        return moves
    }

    /// Receivers release into routes; on runs they throttle down into stalk
    /// blocks (`depthScale` < 1). Excluded roles (the scripted target) skipped.
    private static func routeMoves(_ c: Context, p: Float, depthScale: Float = 1,
                                   exclude: Set<Int> = [], d: TimeInterval) -> [Move] {
        let plans: [(role: Int, depth: Float, bend: Float)] = [
            (7, 12, 3), (8, 14, -3), (9, 6.5, 2), (10, 4.5, 1.5),
        ]
        var moves: [Move] = []
        for plan in plans {
            let idx = c.oBase + plan.role
            guard !exclude.contains(idx) else { continue }
            let start = c.offense[plan.role]
            moves.append((idx,
                          player(start.x + plan.bend * p * depthScale,
                                 lerp(start.z, c.losZ + c.direction * plan.depth * depthScale, p)), d))
        }
        return moves
    }

    private enum CoverageMode { case pass, run }

    /// The back seven reacts: sink into coverage on passes, trigger downhill on runs.
    private static func coverageMoves(_ c: Context, mode: CoverageMode, p: Float,
                                      exclude: Set<Int> = [], d: TimeInterval) -> [Move] {
        var moves: [Move] = []
        // CBs mirror the outside WRs.
        let cbDepth: Float = mode == .pass ? 15 : 6
        for (i, wrRole) in [(0, 7), (1, 8)] {
            let idx = c.cb(i)
            guard !exclude.contains(idx) else { continue }
            let start = c.defense[7 + i]
            moves.append((idx,
                          player(lerp(start.x, c.offense[wrRole].x, p * 0.8),
                                 lerp(start.z, c.losZ + c.direction * cbDepth, p)), d))
        }
        // LBs drop into shallow zones or step downhill.
        let lbDepth: Float = mode == .pass ? 6.5 : 2.5
        for i in 0..<3 {
            let idx = c.lb(i)
            guard !exclude.contains(idx) else { continue }
            let start = c.defense[4 + i]
            moves.append((idx, player(start.x, lerp(start.z, c.losZ + c.direction * lbDepth, p)), d))
        }
        // Safeties stay over the top / rally down.
        let sDepth: Float = mode == .pass ? 15 : 7
        for i in 0..<2 {
            let idx = c.safety(i)
            guard !exclude.contains(idx) else { continue }
            let start = c.defense[9 + i]
            moves.append((idx, player(start.x, lerp(start.z, c.losZ + c.direction * sDepth, p)), d))
        }
        return moves
    }

    /// Unscripted defenders rally toward the ball spot (capped so nobody flies).
    private static func pursuitMoves(_ c: Context, toX x: Float, toZ z: Float,
                                     fraction: Float, exclude: Set<Int> = [],
                                     d: TimeInterval) -> [Move] {
        var moves: [Move] = []
        for role in 0..<11 {
            let idx = c.dBase + role
            guard !exclude.contains(idx) else { continue }
            let start = c.defense[role]
            var tx = lerp(start.x, x, fraction)
            var tz = lerp(start.z, z, fraction)
            let dx = tx - start.x, dz = tz - start.z
            let dist = (dx * dx + dz * dz).squareRoot()
            if dist > 8 {
                tx = start.x + dx / dist * 8
                tz = start.z + dz / dist * 8
            }
            moves.append((idx, player(tx, tz), d))
        }
        return moves
    }

    /// Trailing offense players chase the play downfield.
    private static func trailMoves(_ c: Context, toX x: Float, toZ z: Float,
                                   roles: [Int], fraction: Float, d: TimeInterval) -> [Move] {
        roles.map { role in
            let start = c.offense[role]
            return (c.oBase + role,
                    player(lerp(start.x, x, fraction), lerp(start.z, z, fraction)), d)
        }
    }

    /// The 1-2 chasing defenders closest to the tackle spot (primary tackler
    /// excluded), ranked by pre-snap distance — pursuit has already pulled the
    /// whole defense toward the ball, so the closest starters are the ones at
    /// the pile when the carrier goes down.
    private static func gangTacklers(_ c: Context, x: Float, z: Float,
                                     excluding: Set<Int>) -> [Int] {
        (0..<11)
            .map { role -> (idx: Int, dist: Float) in
                let start = c.defense[role]
                let dx = start.x - x, dz = start.z - z
                return (c.dBase + role, (dx * dx + dz * dz).squareRoot())
            }
            .filter { !excluding.contains($0.idx) }
            .sorted { $0.dist < $1.dist }
            .prefix(2)
            .map(\.idx)
    }

    /// Short closing moves that bring the gang tacklers onto the pile just as
    /// their (staggered) falls begin — they dive in rather than teleport.
    private static func pileOnMoves(_ c: Context, gang: [Int],
                                    x: Float, z: Float) -> [Move] {
        gang.enumerated().map { offset, idx in
            (nodeIndex: idx,
             to: player(x + (offset == 0 ? 0.9 : -0.9), z - c.direction * 0.6),
             duration: 0.45)
        }
    }

    // MARK: - Scripts: Runs

    /// Snap → handoff → run to `endZ` with converging defenders → tackle.
    /// The matchup layer decides the visuals: a big hole blows the DL back, a
    /// stuff lets it penetrate; a QB scramble keeps the ball with the QB.
    /// Returns the carrier and end spot so touchdown/fumble scripts can extend it.
    private static func rushSteps(_ c: Context, endZ: Float, includeTackle: Bool = true)
        -> (steps: [Step], carrier: Int, end: SCNVector3, tackler: Int) {
        let qbStart = c.offenseStart(0)
        // QB scramble when the sim named the QB as the carrier.
        let isScramble = c.carrierRole == 0
        let carrier = isScramble ? c.qb : c.rb
        let carrierStart = isScramble ? qbStart : c.offenseStart(1)
        // A gaping hole (holeSize 1) blows the DL a yard past the LOS; a
        // stuffed front (0) lets it penetrate into the backfield instead.
        let surgeShift = (c.holeSize - 0.4) * 2.2
        var steps: [Step] = []

        // 1. Snap: ball back to the QB; both lines fire off, the receivers
        //    release toward their stalk blocks and the back seven keys run.
        steps.append(Step(
            moves: lineSurgeMoves(c, p: 0.55, d: 0.55, dlShift: surgeShift * 0.4)
                + routeMoves(c, p: 0.3, depthScale: 0.45, d: 0.55)
                + coverageMoves(c, mode: .run, p: 0.35, d: 0.55),
            ballMove: .carry(nodeIndex: c.qb),
            duration: 0.6
        ))

        // 2. Handoff (or the QB tucks it): the line battle resolves — winners
        //    visibly move the front.
        let mesh = isScramble
            ? player(qbStart.x, qbStart.z)
            : player(qbStart.x + 0.8, qbStart.z)
        steps.append(Step(
            moves: merge(
                isScramble ? [] : [(nodeIndex: c.rb, to: mesh, duration: 0.5)],
                lineSurgeMoves(c, p: 1, d: 0.55, dlShift: surgeShift)
                    + routeMoves(c, p: 0.6, depthScale: 0.45, d: 0.55)
                    + coverageMoves(c, mode: .run, p: 0.7, d: 0.55)
            ),
            ballMove: .carry(nodeIndex: carrier),
            duration: 0.6
        ))

        // 3. Run: carrier heads downfield with a slight drift toward the gap;
        //    the credited defender leads the converge, the rest rally.
        let endX = clampX(carrierStart.x + (carrierStart.x <= 0 ? 2 : -2))
        let end = player(endX, endZ)
        let runDuration = TimeInterval(min(max(abs(endZ - mesh.z) * 0.12, 1.0), 2.4))
        let tackler = c.defenseWinnerRole.map { c.dBase + $0 } ?? c.lb(1)
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: carrier, to: end, duration: runDuration),
                    (nodeIndex: tackler, to: player(endX + 0.7, endZ + c.direction * 0.7), duration: runDuration),
                    (nodeIndex: c.dl(1), to: player(endX - 0.8, endZ - c.direction * 0.5), duration: runDuration),
                    (nodeIndex: endX < 0 ? c.safety(0) : c.safety(1),
                     to: player(endX, endZ + c.direction * 1.4), duration: runDuration),
                ],
                routeMoves(c, p: 1, depthScale: 0.45, d: runDuration)
                    + pursuitMoves(c, toX: endX, toZ: endZ, fraction: 0.55, d: runDuration)
                    + (isScramble ? [] : trailMoves(c, toX: endX, toZ: endZ, roles: [0], fraction: 0.3, d: runDuration))
            ),
            ballMove: .carry(nodeIndex: carrier),
            duration: runDuration
        ))

        // 4. Tackle: the hit — carrier and tackler go to the turf, and the
        //    nearest chasers dive onto the pile a beat later (falls stagger
        //    by list order) for a gang-tackle read. The tackler's arms wrap
        //    the carrier, and ~30% of hits first drive him back 0.5-1 yard.
        if includeTackle {
            steps += tackleSteps(c, carrier: carrier, tackler: tackler, x: endX, z: endZ)
        }

        return (steps, carrier, end, tackler)
    }

    /// The shared tackle finish: an optional drive-back (the tackler wraps
    /// up and pushes the carrier 0.5-1 yard backward before the ground), then
    /// the pile with the nearest chasers diving on. ~30% of tackles get the
    /// drive-back — the Madden-2000 push tackle.
    private static func tackleSteps(_ c: Context, carrier: Int, tackler: Int,
                                    x: Float, z: Float) -> [Step] {
        var steps: [Step] = []
        var pileZ = z
        let driveBack = Float.random(in: 0..<1) < 0.3
        if driveBack {
            pileZ = clampZ(z - c.direction * Float.random(in: 0.5...1))
            steps.append(Step(
                moves: [
                    (nodeIndex: carrier, to: player(x, pileZ), duration: 0.4),
                    (nodeIndex: tackler, to: player(x + 0.7, pileZ + c.direction * 0.6), duration: 0.4),
                ],
                ballMove: .carry(nodeIndex: carrier),
                duration: 0.4,
                wraps: [tackler]
            ))
        }
        let gang = gangTacklers(c, x: x, z: pileZ, excluding: [tackler])
        steps.append(Step(moves: pileOnMoves(c, gang: gang, x: x, z: pileZ),
                          ballMove: .carry(nodeIndex: carrier), duration: 1.3,
                          pulses: [tackler],
                          falls: [carrier, tackler] + gang,
                          wraps: driveBack ? gang : [tackler] + gang))
        return steps
    }

    /// QB takes the snap and drops to a knee behind a gentle line surge. ~2s.
    private static func kneelSteps(_ c: Context) -> [Step] {
        let qbStart = c.offenseStart(0)
        return [
            Step(moves: lineSurgeMoves(c, p: 0.3, d: 0.5),
                 ballMove: .carry(nodeIndex: c.qb), duration: 0.6),
            Step(
                moves: [(nodeIndex: c.qb, to: player(qbStart.x, qbStart.z - c.direction * 1), duration: 0.8)],
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.8
            ),
            Step(moves: [], ballMove: .carry(nodeIndex: c.qb), duration: 0.6),
        ]
    }

    // MARK: - Scripts: Passes

    /// Receiver + break depth chosen by target depth: short → slot at ~5,
    /// medium → left WR at ~12, deep → right WR at ~25.
    private static func routePlan(forDepth depth: Float) -> (receiverRole: Int, breakDepth: Float) {
        if depth < 8 { return (9, 5) }
        if depth < 18 { return (7, 12) }
        return (8, 25)
    }

    /// Snap → dropback + route stem → arc to the catch point → run after catch
    /// to `endZ` with a converging DB → tackle.
    private static func completionSteps(_ c: Context, endZ: Float, includeTackle: Bool = true)
        -> (steps: [Step], carrier: Int, end: SCNVector3, defender: Int) {
        let depth = (endZ - c.losZ) * c.direction
        let plan = routePlan(forDepth: depth)
        // The sim names the real target; route the ball to HIS node so the
        // coach watches his actual receiver win (or lose) the rep.
        let receiverRole: Int = {
            if let role = c.carrierRole, [1, 7, 8, 9, 10].contains(role) { return role }
            return plan.receiverRole
        }()
        let receiver = c.oBase + receiverRole
        let breakDepth = min(plan.breakDepth, max(depth - 1, 2))
        let catchDepth = min(breakDepth + 2, max(depth - 0.5, 2))

        let qbStart = c.offenseStart(0)
        let recStart = c.offenseStart(receiverRole)
        let drop: Float = depth >= 18 ? 5 : 3.5
        let qbDrop = player(qbStart.x, qbStart.z - c.direction * drop)
        let stem = player(recStart.x, c.losZ + c.direction * breakDepth)

        // Break angles a few yards toward the middle of the field.
        let catchX = clampX(recStart.x + (recStart.x <= 0 ? 3 : -3))
        let catchPoint = player(catchX, c.losZ + c.direction * catchDepth)

        var steps: [Step] = []

        // 1. Snap: pocket forms, routes release, coverage sinks.
        steps.append(Step(
            moves: pocketMoves(c, p: 0.45, d: 0.45)
                + routeMoves(c, p: 0.25, exclude: [receiver], d: 0.45)
                + coverageMoves(c, mode: .pass, p: 0.4, d: 0.45),
            ballMove: .carry(nodeIndex: c.qb),
            duration: 0.5
        ))

        // 2. Dropback + route stem; the rush gets washed around the pocket.
        //    The QB backpedals his three steps — eyes stay downfield.
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: c.qb, to: qbDrop, duration: 0.8),
                    (nodeIndex: receiver, to: stem, duration: 0.8),
                ],
                pocketMoves(c, p: 1, d: 0.75)
                    + routeMoves(c, p: 0.65, exclude: [receiver], d: 0.75)
                    + coverageMoves(c, mode: .pass, p: 0.75, d: 0.75)
            ),
            ballMove: .carry(nodeIndex: c.qb),
            duration: 0.8,
            backpedals: [c.qb]
        ))

        // 3. Throw: receiver breaks while the ball arcs to the catch point;
        //    every other route and coverage path plays out underneath it.
        let apex = 3 + min(catchDepth, 25) / 25 * 3  // 3-6 by depth
        let flight = TimeInterval(0.5 + catchDepth * 0.02)
        steps.append(Step(
            moves: merge(
                [(nodeIndex: receiver, to: catchPoint, duration: flight)],
                routeMoves(c, p: 1, exclude: [receiver], d: flight)
                    + coverageMoves(c, mode: .pass, p: 1, d: flight)
            ),
            ballMove: .arc(to: air(catchPoint.x, catchPoint.z), apex: apex, duration: flight),
            duration: flight,
            reaches: [receiver]
        ))

        // 4. Run after catch: receiver carries on to the end spot; nearest DB
        //    trails by the separation he conceded — a beaten corner is
        //    visibly behind, blanket coverage arrives with the ball.
        let endX = clampX(catchX + (catchX <= 0 ? 1.5 : -1.5))
        let end = player(endX, endZ)
        let yacDuration = TimeInterval(min(max(abs(endZ - catchPoint.z) * 0.12, 0.8), 2.0))
        let db = catchX < 0 ? c.cb(0) : c.cb(1)
        // Small separation: the DB wraps up at the catch. Big separation: he
        // chases from clearly behind the receiver.
        let trail = 0.6 - c.separation * 0.8
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: receiver, to: end, duration: yacDuration),
                    (nodeIndex: db, to: player(endX + 0.7, endZ + c.direction * trail), duration: yacDuration),
                    (nodeIndex: catchX < 0 ? c.safety(0) : c.safety(1),
                     to: player(endX - 0.6, endZ + c.direction * 1.2), duration: yacDuration),
                ],
                pursuitMoves(c, toX: endX, toZ: endZ, fraction: 0.5, d: yacDuration)
                    + trailMoves(c, toX: endX, toZ: endZ, roles: [0], fraction: 0.25, d: yacDuration)
            ),
            ballMove: .carry(nodeIndex: receiver),
            duration: yacDuration
        ))

        // 5. Tackle: receiver is brought down by the DB — wrap-up arms, an
        //    occasional drive-back, and the nearest chasers piling on late
        //    (staggered falls) for the gang-tackle read.
        if includeTackle {
            steps += tackleSteps(c, carrier: receiver, tackler: db, x: endX, z: endZ)
        }

        return (steps, receiver, end, db)
    }

    /// Same as a completion until the throw — the ball sails 1.5yd past the
    /// break point and slides dead; the receiver lunges but comes up empty.
    private static func incompletionSteps(_ c: Context) -> [Step] {
        // Intended depth from the distance-to-go since no yards were gained.
        let depth = min(max(Float(c.play.distance), 5), 25)
        let plan = routePlan(forDepth: depth)
        let receiverRole: Int = {
            if let role = c.carrierRole, [1, 7, 8, 9, 10].contains(role) { return role }
            return plan.receiverRole
        }()
        let receiver = c.oBase + receiverRole
        let breakDepth = min(plan.breakDepth, max(depth - 1, 2))

        let qbStart = c.offenseStart(0)
        let recStart = c.offenseStart(receiverRole)
        let qbDrop = player(qbStart.x, qbStart.z - c.direction * (depth >= 18 ? 5 : 3.5))
        let stem = player(recStart.x, c.losZ + c.direction * breakDepth)

        // Overthrow: 1.5yd beyond the receiver's break point.
        let missZ = stem.z + c.direction * 1.5
        let miss = air(stem.x, missZ, 0.5)

        return [
            // Snap: pocket forms, routes release, coverage sinks.
            Step(
                moves: pocketMoves(c, p: 0.45, d: 0.55)
                    + routeMoves(c, p: 0.25, exclude: [receiver], d: 0.55)
                    + coverageMoves(c, mode: .pass, p: 0.4, d: 0.55),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.6
            ),
            // Dropback (backpedal, eyes downfield) + route stem.
            Step(
                moves: merge(
                    [
                        (nodeIndex: c.qb, to: qbDrop, duration: 0.9),
                        (nodeIndex: receiver, to: stem, duration: 0.9),
                    ],
                    pocketMoves(c, p: 1, d: 0.85)
                        + routeMoves(c, p: 0.7, exclude: [receiver], d: 0.85)
                        + coverageMoves(c, mode: .pass, p: 0.8, d: 0.85)
                ),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.9,
                backpedals: [c.qb]
            ),
            // Overthrown ball; receiver lunges toward it.
            Step(
                moves: merge(
                    [(nodeIndex: receiver, to: player(stem.x, stem.z + c.direction * 1), duration: 0.7)],
                    routeMoves(c, p: 1, exclude: [receiver], d: 0.7)
                        + coverageMoves(c, mode: .pass, p: 1, d: 0.7)
                ),
                ballMove: .arc(to: miss, apex: 4, duration: 0.7),
                duration: 0.7,
                reaches: [receiver]
            ),
            // Ball skips dead along the turf. No advance.
            Step(
                moves: [],
                ballMove: .slide(to: ground(stem.x, missZ + c.direction * 1.2), duration: 0.5),
                duration: 0.6
            ),
            Step(moves: [], ballMove: nil, duration: 0.5),
        ]
    }

    /// Snap → dropback → the CREDITED rusher beats his blocker and buries the
    /// QB at losZ - direction * |yards|. A decisive win collapses the pocket
    /// visibly faster. Ball never leaves the QB.
    private static func sackSteps(_ c: Context) -> [Step] {
        let sackDepth = max(Float(abs(c.play.yardsGained)), 2)
        let qbStart = c.offenseStart(0)
        let sackSpot = player(qbStart.x, c.losZ - c.direction * sackDepth)
        let rusher = c.dl(c.matchups?.rushWinnerDefRole ?? 2)
        // pocketCollapse 0.7…1.0 → rush closes in 1.0…0.7s.
        let rushTime = TimeInterval(1.7 - c.pocketCollapse)

        return [
            // Snap: protection sets, routes release, coverage sinks.
            Step(
                moves: pocketMoves(c, p: 0.4, d: 0.55)
                    + routeMoves(c, p: 0.3, d: 0.55)
                    + coverageMoves(c, mode: .pass, p: 0.5, d: 0.55),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.6
            ),
            // Dropback (backpedal) while the rusher knifes through a
            // collapsing pocket.
            Step(
                moves: merge(
                    [
                        (nodeIndex: c.qb, to: sackSpot, duration: rushTime),
                        (nodeIndex: rusher, to: player(sackSpot.x + 1, sackSpot.z + c.direction * 1.5), duration: rushTime),
                    ],
                    pocketMoves(c, p: 1, d: rushTime)
                        + routeMoves(c, p: 0.8, d: rushTime)
                        + coverageMoves(c, mode: .pass, p: 0.9, d: rushTime)
                ),
                ballMove: .carry(nodeIndex: c.qb),
                duration: rushTime,
                backpedals: [c.qb]
            ),
            // Rusher closes the last yard; receivers finish their routes with
            // nowhere to go.
            Step(
                moves: merge(
                    [(nodeIndex: rusher, to: player(sackSpot.x + 0.4, sackSpot.z), duration: 0.8)],
                    routeMoves(c, p: 1, d: 0.75)
                        + coverageMoves(c, mode: .pass, p: 1, d: 0.75)
                ),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.8
            ),
            // Sack: the QB is buried; both hit the turf, the rusher wrapped
            // around him.
            Step(moves: [], ballMove: .carry(nodeIndex: c.qb), duration: 1.3,
                 pulses: [rusher], falls: [c.qb, rusher], wraps: [rusher]),
            Step(moves: [], ballMove: .carry(nodeIndex: c.qb), duration: 0.4),
        ]
    }

    /// Like a completion, but the CREDITED DB jumps the route: the ball arcs
    /// straight to him and he returns it ~5yd the other way.
    private static func interceptionSteps(_ c: Context) -> [Step] {
        let depth = min(max(Float(c.play.distance), 8), 25)
        let plan = routePlan(forDepth: depth)
        let receiverRole: Int = {
            if let role = c.carrierRole, [1, 7, 8, 9, 10].contains(role) { return role }
            return plan.receiverRole
        }()
        let receiver = c.oBase + receiverRole
        let breakDepth = min(plan.breakDepth, max(depth - 1, 2))

        let qbStart = c.offenseStart(0)
        let recStart = c.offenseStart(receiverRole)
        let qbDrop = player(qbStart.x, qbStart.z - c.direction * (depth >= 18 ? 5 : 3.5))
        let stem = player(recStart.x, c.losZ + c.direction * breakDepth)

        // The DB undercuts the route at the catch point.
        let catchX = clampX(recStart.x + (recStart.x <= 0 ? 3 : -3))
        let catchZ = c.losZ + c.direction * min(breakDepth + 2, depth)
        let pick = player(catchX, catchZ)
        let db = c.matchups?.pickDefRole.map { c.dBase + $0 }
            ?? (recStart.x < 0 ? c.cb(0) : c.cb(1))

        let returnSpot = player(catchX, catchZ - c.direction * 5)
        return [
            // Snap: pocket forms, routes release, coverage sinks.
            Step(
                moves: pocketMoves(c, p: 0.45, d: 0.55)
                    + routeMoves(c, p: 0.25, exclude: [receiver], d: 0.55)
                    + coverageMoves(c, mode: .pass, p: 0.4, exclude: [db], d: 0.55),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.6
            ),
            // Dropback (backpedal) + stem; the DB is already breaking on the ball.
            Step(
                moves: merge(
                    [
                        (nodeIndex: c.qb, to: qbDrop, duration: 0.9),
                        (nodeIndex: receiver, to: stem, duration: 0.9),
                        (nodeIndex: db, to: pick, duration: 0.9),
                    ],
                    pocketMoves(c, p: 1, d: 0.85)
                        + routeMoves(c, p: 0.7, exclude: [receiver], d: 0.85)
                        + coverageMoves(c, mode: .pass, p: 0.8, exclude: [db], d: 0.85)
                ),
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.9,
                backpedals: [c.qb]
            ),
            // Throw sails right to the DB.
            Step(
                moves: merge(
                    [(nodeIndex: receiver, to: player(catchX, catchZ - c.direction * 1.5), duration: 0.7)],
                    routeMoves(c, p: 1, exclude: [receiver], d: 0.7)
                        + coverageMoves(c, mode: .pass, p: 1, exclude: [db], d: 0.7)
                ),
                ballMove: .arc(to: air(pick.x, pick.z), apex: 4.5, duration: 0.7),
                duration: 0.7,
                reaches: [db, receiver]
            ),
            // Return: DB takes it back the other way ~5yd while the offense
            // scrambles after him; pulse the DB.
            Step(
                moves: merge(
                    [(nodeIndex: db, to: returnSpot, duration: 1.0)],
                    trailMoves(c, toX: returnSpot.x, toZ: returnSpot.z,
                               roles: Array(Set([0, receiverRole, 9])), fraction: 0.5, d: 1.0)
                ),
                ballMove: .carry(nodeIndex: db),
                duration: 1.0,
                pulses: [db]
            ),
            Step(moves: [], ballMove: .carry(nodeIndex: db), duration: 0.5),
        ]
    }

    // MARK: - Scripts: Turnovers & Scores

    /// Rush script to the tackle spot, then the ball pops loose, slides 2yd,
    /// and a defender scoops it for a beat.
    private static func fumbleSteps(_ c: Context, endZ: Float) -> [Step] {
        let rush = rushSteps(c, endZ: endZ, includeTackle: false)
        var steps = rush.steps

        // The hit: ball detaches and slides loose while a defender closes in.
        let looseX = clampX(rush.end.x + 2)
        let looseZ = clampZ(rush.end.z + c.direction * 0.5)
        let recoverer = c.lb(0)
        steps.append(Step(
            moves: [(nodeIndex: recoverer, to: player(looseX, looseZ), duration: 0.7)],
            ballMove: .slide(to: ground(looseX, looseZ), duration: 0.6),
            duration: 0.7,
            pulses: [rush.tackler]
        ))

        // Scoop: the ball rides with the recoverer for one beat.
        steps.append(Step(
            moves: [(nodeIndex: recoverer, to: player(looseX, looseZ - c.direction * 2), duration: 0.6)],
            ballMove: .carry(nodeIndex: recoverer),
            duration: 0.6,
            pulses: [recoverer]
        ))

        return steps
    }

    /// Rush or completion script (by play type) into the end zone, then a
    /// two-pulse celebration and a ball spike. The caller should
    /// `focusCamera` on the end zone when this timeline runs.
    private static func touchdownSteps(_ c: Context) -> [Step] {
        // End spot: 2 yards past the goal line.
        let endZ = clampZ(c.direction * 52)

        // A two-point try carries the special-teams play type; the called
        // play decides whether it looks like a throw or a plunge.
        let passLike = c.play.playType == .pass
            || (c.play.playType == .twoPointConversion && c.call?.isPass == true)

        let script: (steps: [Step], carrier: Int, end: SCNVector3)
        if passLike {
            let pass = completionSteps(c, endZ: endZ, includeTackle: false)
            script = (pass.steps, pass.carrier, pass.end)
        } else {
            let run = rushSteps(c, endZ: endZ, includeTackle: false)
            script = (run.steps, run.carrier, run.end)
        }

        var steps = script.steps

        // Celebration: the scorer leaps with his arms up while teammates
        // sprint in to mob him…
        let carrierRole = script.carrier - c.oBase
        let mates = [1, 9, 7, 8, 0].filter { $0 != carrierRole }.prefix(3)
        steps.append(Step(
            moves: trailMoves(c, toX: script.end.x, toZ: script.end.z,
                              roles: Array(mates), fraction: 0.85, d: 1.3),
            ballMove: .carry(nodeIndex: script.carrier),
            duration: 0.45,
            pulses: [script.carrier],
            celebrates: [script.carrier]
        ))
        steps.append(Step(moves: [], ballMove: .carry(nodeIndex: script.carrier), duration: 0.45, pulses: [script.carrier]))

        // …then spikes the ball into the turf — up ~3yd and straight down.
        steps.append(Step(
            moves: [],
            ballMove: .arc(to: ground(script.end.x, script.end.z), apex: 3, duration: 0.6),
            duration: 0.7
        ))

        return steps
    }

    // MARK: - Scripts: Special Teams

    /// Long snap to the punter → high arc downfield → returner catches and
    /// brings it back ~3yd.
    private static func puntSteps(_ c: Context) -> [Step] {
        let punterSpot = c.offenseStart(0)  // formation already puts the QB 7yd back

        // Punt distance: use the sim's yardage when plausible, else 40.
        let reported = Float(c.play.yardsGained)
        let distance: Float = reported > 10 ? min(max(reported, 35), 45) : 40
        let landZ = clampZ(c.losZ + c.direction * distance)
        let returner = c.safety(0)

        // Coverage: everyone on the kicking team but the punter sprints
        // downfield — gunners (outside WRs) lead the charge.
        var coverage: [Move] = []
        for role in 1...10 {
            let start = c.offense[role]
            let depth: Float = (role == 7 || role == 8) ? 2 : 6
            coverage.append((c.oBase + role,
                             player(start.x * 0.85, clampZ(landZ - c.direction * depth)), 1.6))
        }
        // Return unit falls back to wall off in front of the returner.
        var wall: [Move] = []
        for role in 0..<11 where c.dBase + role != returner {
            let start = c.defense[role]
            wall.append((c.dBase + role,
                         player(lerp(start.x, Float(role % 3 - 1) * 4, 0.5),
                                lerp(start.z, clampZ(landZ - c.direction * 7), 0.7)), 1.6))
        }

        let returnEnd = player(1, landZ - c.direction * 3)
        return [
            // Long snap slides back to the punter.
            Step(
                moves: [],
                ballMove: .slide(to: ground(punterSpot.x, punterSpot.z), duration: 0.5),
                duration: 0.6
            ),
            // Boot: high arc downfield; coverage races under it while the
            // return unit sets its wall and the returner settles.
            Step(
                moves: merge([(nodeIndex: returner, to: player(0, landZ), duration: 1.6)],
                             coverage + wall),
                ballMove: .arc(to: air(0, landZ), apex: 12, duration: 1.6),
                duration: 1.6
            ),
            // Catch and a short ~3yd return; the coverage rallies to the ball.
            Step(
                moves: merge(
                    [(nodeIndex: returner, to: returnEnd, duration: 1.0)],
                    (1...10).map { role in
                        let start = c.offense[role]
                        return (c.oBase + role,
                                player(lerp(start.x * 0.85, returnEnd.x, 0.45),
                                       lerp(clampZ(landZ - c.direction * 6), returnEnd.z, 0.45)), 1.0)
                    }
                ),
                ballMove: .carry(nodeIndex: returner),
                duration: 1.0
            ),
            Step(moves: [], ballMove: .carry(nodeIndex: returner), duration: 0.4),
        ]
    }

    /// Snap back to the holder, then the kick arcs at the goalposts:
    /// good → through the middle, missed → wide of the upright. ~3s total.
    private static func fieldGoalSteps(_ c: Context, good: Bool) -> [Step] {
        let holdSpot = c.offenseStart(0)  // formation puts the holder 3yd back
        let postZ = clampZ(c.direction * 60)  // clamps to ±58, just shy of the posts
        let targetX: Float = good ? 0 : 7     // wide of the upright at x ≈ 3.1
        let targetY: Float = good ? 4 : 2.5   // above/below crossbar height

        return [
            // Snap to the hold.
            Step(
                moves: [],
                ballMove: .slide(to: ground(holdSpot.x, holdSpot.z), duration: 0.45),
                duration: 0.5
            ),
            // Hold beat.
            Step(moves: [], ballMove: nil, duration: 0.35),
            // The kick: both lines surge into the pile as it goes up.
            Step(
                moves: lineSurgeMoves(c, p: 0.8, d: 0.5),
                ballMove: .arc(to: SCNVector3(clampX(targetX), targetY, postZ), apex: 8, duration: 1.6),
                duration: 1.7
            ),
            Step(moves: [], ballMove: nil, duration: 0.45),
        ]
    }

    // MARK: - Scripts: Kickoffs

    /// World Z of the kicking tee (the kicking team's own 35-yard line).
    static func kickoffSpotZ(kickingTeamIsHome: Bool) -> Float {
        kickingTeamIsHome ? -15 : 15
    }

    /// Kicking team layout in node-role order: 0 = kicker in his run-up,
    /// 1-10 = the coverage line spread across the tee line.
    private static func kickoffKickingPositions(kickDir: Float) -> [(x: Float, z: Float, number: Int)] {
        let teeZ = -kickDir * 15
        let lanes: [Float] = [-22, -17.5, -13, -8.5, -4, 4, 8.5, 13, 17.5, 22]
        let numbers = [41, 45, 52, 38, 29, 31, 47, 55, 44, 26]
        var out: [(x: Float, z: Float, number: Int)] = [(0, teeZ - kickDir * 6, 3)]
        for (i, x) in lanes.enumerated() {
            out.append((x, teeZ - kickDir * 1, numbers[i]))
        }
        return out.map { (clampX($0.x), clampZ($0.z), $0.number) }
    }

    /// Receiving team layout in node-role order: 0-4 = front line at their own
    /// 35, 5-8 = wedge wave at the 20, 9 = upback, 10 = deep returner.
    private static func kickoffReceivingPositions(kickDir: Float) -> [(x: Float, z: Float, number: Int)] {
        // Receiving team's own yard Y -> world z.
        func ownYard(_ y: Float) -> Float { kickDir * (50 - y) }
        var out: [(x: Float, z: Float, number: Int)] = []
        let frontX: [Float] = [-16, -8, 0, 8, 16]
        let frontNumbers = [58, 63, 72, 68, 77]
        for (i, x) in frontX.enumerated() { out.append((x, ownYard(35), frontNumbers[i])) }
        let waveX: [Float] = [-12, -4, 4, 12]
        let waveNumbers = [35, 27, 49, 42]
        for (i, x) in waveX.enumerated() { out.append((x, ownYard(20), waveNumbers[i])) }
        out.append((-3, ownYard(10), 22)) // upback
        out.append((0, ownYard(2), 30))   // deep returner
        return out.map { (clampX($0.x), clampZ($0.z), $0.number) }
    }

    /// Pre-kick lineup for both teams (kicking team on its own 35).
    static func kickoffFormation(kickingTeamIsHome: Bool)
        -> (home: [(x: Float, z: Float, number: Int)], away: [(x: Float, z: Float, number: Int)]) {
        let kickDir: Float = kickingTeamIsHome ? 1 : -1
        let kicking = kickoffKickingPositions(kickDir: kickDir)
        let receiving = kickoffReceivingPositions(kickDir: kickDir)
        return kickingTeamIsHome ? (home: kicking, away: receiving) : (home: receiving, away: kicking)
    }

    /// Kickoff timeline: ball to the tee → booming hang-time kick with the
    /// coverage flying down in lanes and the return unit folding into a wedge →
    /// catch → return out to `returnYardLine` (receiving team's own yard line),
    /// a touchback kneel, or a housed return TD. The view moves both teams into
    /// `kickoffFormation` first, then runs these steps.
    static func kickoffSteps(kickingTeamIsHome: Bool, returnYardLine: Int,
                             isTouchback: Bool, isReturnTouchdown: Bool)
        -> [FootballFieldScene.PlayStep] {
        let kickDir: Float = kickingTeamIsHome ? 1 : -1
        let kBase = kickingTeamIsHome ? 0 : 11
        let rBase = kickingTeamIsHome ? 11 : 0
        let kicking = kickoffKickingPositions(kickDir: kickDir)
        let receiving = kickoffReceivingPositions(kickDir: kickDir)
        let teeZ = -kickDir * 15
        let returner = rBase + 10
        func ownYard(_ y: Float) -> Float { kickDir * (50 - y) }

        // Touchbacks are fielded in the end zone; returns near the goal line.
        let catchZ = clampZ(isTouchback ? ownYard(-3) : ownYard(2))

        var steps: [Step] = []

        // 1. Ball to the tee while the kicker walks into his run-up.
        steps.append(Step(
            moves: [(kBase, player(0, teeZ - kickDir * 1.2), 0.5)],
            ballMove: .slide(to: ground(0, teeZ), duration: 0.4),
            duration: 0.6
        ))

        // 2. Boot: high hanging kick. Ten coverage men fly downfield in their
        //    lanes, the kicker trails as the safety, the front line folds back
        //    into the wedge and the returner settles under the ball.
        var bootMoves: [Move] = [(returner, player(0, catchZ), 2.0)]
        for i in 1...10 {
            bootMoves.append((kBase + i, player(kicking[i].x * 0.8, clampZ(ownYard(22))), 2.0))
        }
        bootMoves.append((kBase, player(0, teeZ + kickDir * 4), 2.0))
        for i in 0..<5 {
            bootMoves.append((rBase + i, player(receiving[i].x * 0.55, clampZ(ownYard(18))), 2.0))
        }
        for i in 5..<9 {
            bootMoves.append((rBase + i, player(receiving[i].x * 0.7, clampZ(ownYard(10))), 2.0))
        }
        bootMoves.append((rBase + 9, player(-2, clampZ(ownYard(6))), 2.0))
        steps.append(Step(
            moves: bootMoves,
            ballMove: .arc(to: air(0, catchZ), apex: 16, duration: 2.0),
            duration: 2.0,
            reaches: [returner]
        ))

        if isTouchback {
            // 3. Kneel in the end zone; the coverage pulls up.
            steps.append(Step(moves: [], ballMove: .carry(nodeIndex: returner), duration: 0.9))
            steps.append(Step(moves: [], ballMove: .carry(nodeIndex: returner), duration: 0.5))
            return steps
        }

        // 3. Return: out to the drive start (or all the way on a housed kick)
        //    with the coverage converging and the wedge escorting.
        let endYard: Float = isReturnTouchdown ? 102 : Float(returnYardLine)
        let endZ = clampZ(ownYard(endYard))
        let endX: Float = isReturnTouchdown ? 6 : 4
        let runDistance = abs(endZ - catchZ)
        let runDuration = TimeInterval(min(max(runDistance * 0.06, 1.0), 3.2))
        // A housed return leaves the coverage trailing; a normal one rallies in.
        let convergence: Float = isReturnTouchdown ? 0.35 : 0.75
        var returnMoves: [Move] = [(returner, player(endX, endZ), runDuration)]
        for i in 1...10 {
            let laneX = kicking[i].x * 0.8
            let fromZ = clampZ(ownYard(22))
            returnMoves.append((kBase + i,
                                player(lerp(laneX, endX, convergence),
                                       lerp(fromZ, endZ, convergence)), runDuration))
        }
        for i in 0..<5 {
            returnMoves.append((rBase + i,
                                player(receiving[i].x * 0.5,
                                       lerp(clampZ(ownYard(18)), endZ, 0.5)), runDuration))
        }
        steps.append(Step(
            moves: returnMoves,
            ballMove: .carry(nodeIndex: returner),
            duration: runDuration,
            pulses: isReturnTouchdown ? [returner] : []
        ))

        if isReturnTouchdown {
            // Breakaway finish: leap + pulse in the end zone (the view runs
            // the camera push and confetti).
            steps.append(Step(moves: [], ballMove: .carry(nodeIndex: returner),
                              duration: 0.6, pulses: [returner], celebrates: [returner]))
        } else {
            // 4. The nearest lane defenders wrap the returner up.
            let tacklers = [kBase + 5, kBase + 6]
            var tackleMoves: [Move] = []
            for (i, idx) in tacklers.enumerated() {
                tackleMoves.append((idx,
                                    player(endX + (i == 0 ? 0.9 : -0.9), endZ + kickDir * 0.6),
                                    0.45))
            }
            steps.append(Step(
                moves: tackleMoves,
                ballMove: .carry(nodeIndex: returner),
                duration: 1.2,
                pulses: [tacklers[0]],
                falls: [returner] + tacklers,
                wraps: tacklers
            ))
        }

        return steps
    }

    // MARK: - Scripts: Clock Plays

    /// Snap, then the ball goes straight into the turf. ~1.5s.
    private static func spikeSteps(_ c: Context) -> [Step] {
        let qbStart = c.offenseStart(0)
        return [
            Step(moves: lineSurgeMoves(c, p: 0.3, d: 0.4),
                 ballMove: .carry(nodeIndex: c.qb), duration: 0.4),
            Step(
                moves: [],
                ballMove: .slide(to: ground(qbStart.x, qbStart.z), duration: 0.4),
                duration: 0.5
            ),
            Step(moves: [], ballMove: nil, duration: 0.6),
        ]
    }

    /// Fallback for outcomes with no bespoke script (penalties etc.):
    /// snap to the QB behind a brief line surge, then hold.
    private static func defaultSteps(_ c: Context) -> [Step] {
        [
            Step(moves: lineSurgeMoves(c, p: 0.5, d: 0.55),
                 ballMove: .carry(nodeIndex: c.qb), duration: 0.6),
            Step(moves: [], ballMove: .carry(nodeIndex: c.qb), duration: 1.0),
        ]
    }

    // MARK: - Geometry Helpers

    private static func clampX(_ x: Float) -> Float {
        min(max(x, Bounds.minX), Bounds.maxX)
    }

    private static func clampZ(_ z: Float) -> Float {
        min(max(z, Bounds.minZ), Bounds.maxZ)
    }

    /// A clamped on-field position at player capsule height.
    private static func player(_ x: Float, _ z: Float) -> SCNVector3 {
        SCNVector3(clampX(x), playerY, clampZ(z))
    }

    /// A clamped position with the ball resting on the turf.
    private static func ground(_ x: Float, _ z: Float) -> SCNVector3 {
        SCNVector3(clampX(x), ballGroundY, clampZ(z))
    }

    /// A clamped position at catch/carry height (or a custom height for kicks).
    private static func air(_ x: Float, _ z: Float, _ y: Float = ballCarryY) -> SCNVector3 {
        SCNVector3(clampX(x), y, clampZ(z))
    }
}
