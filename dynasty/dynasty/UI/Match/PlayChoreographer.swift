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

    // MARK: - Physical Pacing

    /// Ball velocity of a thrown pass (yd/s): ~20 air yards ≈ 1.1 s.
    private static let passVelocity: Float = 18

    /// Role-ordered fallback top speeds (yd/s) when the view supplies no
    /// attribute feed: OL crawl ~6.5, the fastest WR/CB run ~9.5.
    /// Offense: 0=QB 1=RB 2-6=OL 7/8=WR 9=slot 10=TE.
    static let defaultOffenseSpeeds: [Float] = [7.6, 8.8, 6.6, 6.5, 6.5, 6.5, 6.6, 9.2, 9.2, 9.0, 8.1]
    /// Defense: 0-3=DL 4-6=LB 7-8=CB 9-10=S.
    static let defaultDefenseSpeeds: [Float] = [7.3, 6.8, 6.8, 7.3, 8.2, 8.0, 8.2, 9.2, 9.2, 9.0, 9.0]

    /// Cheap deterministic 0…1 hash for per-player reaction/jitter variation.
    private static func hash01(_ seed: Int) -> Float {
        var x = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 0x9E37)
        x ^= x >> 13
        x = x &* 0x9E3779B97F4A7C15
        x ^= x >> 31
        return Float(x % 1024) / 1023.0
    }

    /// Arc-length fractions at each step boundary for a runner covering
    /// `total` yards at his own `speed` — he runs his route at HIS pace and
    /// simply finishes when it's done (min'd at 1), instead of stretching to
    /// fill the play like the uniform schedule does.
    private static func speedFractions(_ durations: [TimeInterval], total: Float,
                                       speed: Float) -> [Float] {
        var elapsed: TimeInterval = 0
        return durations.map {
            elapsed += $0
            return min(Float(elapsed) * speed / max(total, 0.01), 1)
        }
    }

    /// Snap reaction time for one man: deterministic from role + his speed
    /// feed, in football order — the OL knows the count (fastest), the QB
    /// starts the play, backs/receivers fire off next, the defensive line
    /// reads the ball, the linebackers read the play, and the secondary
    /// reads routes (slowest).
    private static func reaction(role: Int, isOffense: Bool, speed: Float) -> TimeInterval {
        let band: ClosedRange<TimeInterval>
        if isOffense {
            switch role {
            case 0: return 0.02              // QB initiates
            case 2...6: band = 0.05...0.10   // OL
            case 1, 10: band = 0.08...0.16   // RB / TE
            default: band = 0.10...0.20      // WRs
            }
        } else {
            switch role {
            case 0...3: band = 0.08...0.16   // DL
            case 4...6: band = 0.14...0.24   // LBs
            default: band = 0.18...0.30      // secondary
            }
        }
        let t = TimeInterval(hash01(role * 31 + Int(speed * 13) + (isOffense ? 0 : 7)))
        return band.lowerBound + (band.upperBound - band.lowerBound) * t
    }

    /// All 22 reaction delays for a snap step, keyed by scene node index.
    private static func snapReactionDelays(_ c: Context) -> [Int: TimeInterval] {
        var out: [Int: TimeInterval] = [:]
        for role in 0..<11 {
            out[c.oBase + role] = reaction(role: role, isOffense: true, speed: c.oSpeed(role))
            out[c.dBase + role] = reaction(role: role, isOffense: false, speed: c.dSpeed(role))
        }
        return out
    }

    /// Per-player lateral route jitter, ±0.3 yd deterministic — two men on
    /// the same concept never trace pixel-identical stems.
    private static func lateralJitter(role: Int, c: Context) -> Float {
        hash01(role * 17 + Int(c.oSpeed(role) * 7)) * 0.6 - 0.3
    }

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
    /// split stance. The QB stays tall in the gun (upright by omission) but
    /// bends over the C with his hands out when the CALL puts him under
    /// center — the snap exchange starts from that pose.
    static func stances(offenseIsHome: Bool, call: OffensivePlayCall? = nil)
        -> (home: [Int: FootballFieldScene.Stance], away: [Int: FootballFieldScene.Stance]) {
        var offense: [Int: FootballFieldScene.Stance] = [1: .twoPoint, 10: .threePoint]
        switch call {
        case .insideRun, .qbSneak, .dive, .kneel:
            offense[0] = .underCenter
        default:
            break
        }
        for role in 2...6 { offense[role] = .threePoint }   // OL
        for role in [7, 8, 9] { offense[role] = .split }    // WRs
        var defense: [Int: FootballFieldScene.Stance] = [:]
        for role in 0...3 { defense[role] = .threePoint }   // DL
        for role in [4, 5, 6, 9, 10] { defense[role] = .twoPoint }  // LBs + safeties
        for role in [7, 8] { defense[role] = .split }       // CBs
        return offenseIsHome ? (home: offense, away: defense) : (home: defense, away: offense)
    }

    /// Position-silhouette body builds keyed by per-team node index: OL/DL
    /// are HEAVY (wide trunk, thick limbs), QB/RB/TE/LB stay MEDIUM, and
    /// WR/CB/S run LEAN — the coach camera tells the trenches from the
    /// skill players at a glance. Same slot convention as `stances`.
    static func bodyTypes(offenseIsHome: Bool)
        -> (home: [Int: FootballFieldScene.BodyType], away: [Int: FootballFieldScene.BodyType]) {
        var offense: [Int: FootballFieldScene.BodyType] = [0: .medium, 1: .medium, 10: .medium]
        for role in 2...6 { offense[role] = .heavy }        // OL
        for role in [7, 8, 9] { offense[role] = .lean }     // WRs
        var defense: [Int: FootballFieldScene.BodyType] = [:]
        for role in 0...3 { defense[role] = .heavy }        // DL
        for role in 4...6 { defense[role] = .medium }       // LBs
        for role in 7...10 { defense[role] = .lean }        // CBs + safeties
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

    /// Offensive huddle ring ~7 yards behind the ball (clamped inside the
    /// field): 11 tight ellipse spots around the ring center, in node role
    /// order. The view gathers the offense here between plays for ~1.2 s
    /// and then breaks it into the next formation; hurry-up skips it.
    static func huddlePositions(losZ: Float, direction: Float) -> [(x: Float, z: Float)] {
        let centerZ = clampZ(losZ - direction * 7)
        return (0..<11).map { role in
            let angle = Float(role) / 11 * 2 * Float.pi
            return (x: clampX(sin(angle) * 2.0), z: clampZ(centerZ + cos(angle) * 1.5))
        }
    }

    /// Offense role order: 0=QB, 1=RB, 2-6=OL, 7=WR left, 8=WR right, 9=slot, 10=TE.
    /// The alignment reflects the CALL: under-center I-form for interior runs,
    /// compressed splits for the ground game, spread shotgun for deep shots.
    /// Internal (not private) so `RouteSpec.diagram` projects the play card
    /// from the exact same alignments the field uses.
    static func offensePositions(for playType: PlayType, call: OffensivePlayCall? = nil,
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
            case .cross:
                // Slot flips to the right so the two crossers X the field.
                qbDepth = 5; wrSplit = 16; slot = (8, 1.5)
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
                      defensivePackage: DefensivePackage? = nil,
                      offenseSpeeds: [Float]? = nil,
                      defenseSpeeds: [Float]? = nil)
        -> [FootballFieldScene.PlayStep] {
        let context = Context(play: play, losYardLine: losYardLine, offenseIsHome: offenseIsHome,
                              matchups: matchups, call: call, defensivePackage: defensivePackage,
                              offenseSpeeds: offenseSpeeds, defenseSpeeds: defenseSpeeds)
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
        /// The defense's dialed package (shapes coverage/blitz choreography).
        let package: DefensivePackage?
        /// The play's route map — the called play's spec, or a depth-tiered
        /// generic concept when nobody dialed a call (AI drives).
        let spec: RouteSpec
        /// Role-ordered top speeds (yd/s) fed from the real units' speed
        /// attributes; defaults when the caller supplies none.
        let offenseSpeeds: [Float]
        let defenseSpeeds: [Float]

        func oSpeed(_ role: Int) -> Float {
            offenseSpeeds.indices.contains(role) ? offenseSpeeds[role]
                : PlayChoreographer.defaultOffenseSpeeds[role]
        }

        func dSpeed(_ role: Int) -> Float {
            defenseSpeeds.indices.contains(role) ? defenseSpeeds[role]
                : PlayChoreographer.defaultDefenseSpeeds[role]
        }

        init(play: PlayResult, losYardLine: Int, offenseIsHome: Bool,
             matchups: PlayMatchups? = nil,
             call: OffensivePlayCall? = nil,
             defensivePackage: DefensivePackage? = nil,
             offenseSpeeds: [Float]? = nil,
             defenseSpeeds: [Float]? = nil) {
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
            self.package = defensivePackage
            self.offenseSpeeds = offenseSpeeds ?? PlayChoreographer.defaultOffenseSpeeds
            self.defenseSpeeds = defenseSpeeds ?? PlayChoreographer.defaultDefenseSpeeds
            if let call {
                self.spec = RouteSpec.spec(for: call)
            } else {
                let depth = play.yardsGained > 0 ? Float(play.yardsGained) : Float(max(play.distance, 5))
                self.spec = RouteSpec.generic(forDepth: min(max(depth, 4), 25))
            }
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

        /// True when the QB takes the snap under center (hand-to-hand
        /// exchange); false = shotgun, the snap is a low toss back to him.
        var qbUnderCenter: Bool { (losZ - offense[0].z) * direction < 2.5 }

        /// The C→QB exchange for this alignment.
        var snapExchange: FootballFieldScene.BallMove {
            .snap(toNodeIndex: qb, shotgun: !qbUnderCenter)
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

        /// Pre-snap world position of a defense role (0-10) as a flat pair.
        func defenseStart(_ role: Int) -> (x: Float, z: Float) {
            (defense[role].x, defense[role].z)
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

    /// Pass protection: the OL sets a pocket (tackles deeper than the
    /// interior) and each rusher works to HIS blocker's set point — the
    /// OL/DL pairs lock up chest to chest (the step's `blocks` list adds the
    /// punch-and-shove pose on top). When `beatenBlocker` names an OL role
    /// (2-6), THAT side caves visibly deeper and his man drives THROUGH the
    /// spot (the sack collapse side).
    private static func pocketMoves(_ c: Context, p: Float, d: TimeInterval,
                                    beatenBlocker: Int? = nil) -> [Move] {
        var moves: [Move] = []
        // OL set points (role → final spot).
        var setPoints: [Int: (x: Float, z: Float)] = [:]
        for i in 0..<5 {
            let start = c.offense[2 + i]
            var depth: Float = (i == 0 || i == 4) ? 1.9 : 1.2
            var widen = Float(i - 2) * 0.35
            if beatenBlocker == 2 + i {
                depth = 3.3
                widen *= 1.6
            }
            let spot = (x: start.x + widen, z: c.losZ - c.direction * depth)
            setPoints[2 + i] = spot
            moves.append((c.oBase + 2 + i,
                          player(lerp(start.x, spot.x, p), lerp(start.z, spot.z, p)), d))
        }
        // Rushers engage their pair a step in front of the set point, edges
        // shading outside; a winner presses through into the QB's lap.
        for i in 0..<4 {
            let start = c.defense[i]
            let blocker = blockerFacing(defRole: i)
            let spot = setPoints[blocker] ?? (x: start.x, z: c.losZ - c.direction * 1.6)
            let wide: Float = i == 0 ? -0.8 : (i == 3 ? 0.8 : 0)
            let press: Float = blocker == beatenBlocker ? -1.0 : 0.8
            moves.append((c.dl(i),
                          player(lerp(start.x, spot.x + wide, p),
                                 lerp(start.z, spot.z + c.direction * press, p)), d))
        }
        return moves
    }

    /// The OL role squared up across from a DL role — spatial pairing (the
    /// -4.5 DE works the LT, the -1.5 DT the LG, and so on), shared by the
    /// pocket engagement and the sack collapse side.
    private static func blockerFacing(defRole: Int) -> Int {
        switch defRole {
        case 0: return 2   // DE over the left tackle
        case 1: return 3   // DT over the left guard
        case 2: return 5   // DT over the right guard
        default: return 6  // DE over the right tackle
        }
    }

    /// Both lines' node indexes — the step's `blocks` list (punch + shove).
    private static func lineBlockNodes(_ c: Context) -> [Int] {
        (2...6).map { c.oBase + $0 } + (0...3).map { c.dl($0) }
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

    // MARK: - Route Engine (spec-driven)
    //
    // Pass plays run every eligible receiver's FULL spec route as waypoint
    // paths, and the defense plays its actual call: man mirrors trail their
    // men by a distance read from the play's matchup events, zone shells
    // drop to landmarks (the nearest man breaking when the ball is in the
    // air), and blitzers rush through the spec'd gaps. All of it is
    // presentation — outcome, target and yardage come from the sim.

    private typealias PathMove = (nodeIndex: Int, points: [SCNVector3], duration: TimeInterval)

    /// Field-space route path for an offense role, or nil when he blocks.
    /// Interior waypoints carry the player's deterministic ±0.3 yd lateral
    /// jitter (start and end stay exact — alignment and catch points hold),
    /// so no two runners trace identical rails or stack inside each other.
    private static func specPath(role: Int, c: Context, depthScale: Float = 1) -> RoutePath? {
        let start = c.offense[role]
        guard let pts = c.spec.points(role: role, startX: start.x, startZ: start.z,
                                      losZ: c.losZ, direction: c.direction,
                                      depthScale: depthScale) else { return nil }
        var mapped = pts.map { (x: clampX($0.x), z: clampZ($0.z)) }
        if mapped.count > 2 {
            let jitter = lateralJitter(role: role, c: c)
            for index in 1..<(mapped.count - 1) {
                mapped[index].x = clampX(mapped[index].x + jitter)
            }
        }
        return RoutePath(points: mapped)
    }

    /// Checkdown path when the sim targeted a role the spec has blocking.
    private static func fallbackPath(role: Int, c: Context, depthScale: Float = 1) -> RoutePath {
        let start = c.offense[role]
        let pts = RouteSpec.resolve(RouteSpec.checkdown(role: role),
                                    startX: start.x, startZ: start.z,
                                    losZ: c.losZ, direction: c.direction,
                                    depthScale: depthScale)
        return RoutePath(points: pts.map { (clampX($0.x), clampZ($0.z)) })
    }

    /// Cuts a full-play path at explicit arc-length fractions per step, so
    /// the runner covers it continuously across sequential steps.
    private static func pathMoves(_ path: RoutePath, nodeIndex: Int,
                                  fractions: [Float], durations: [TimeInterval]) -> [PathMove?] {
        var out: [PathMove?] = []
        var previous: Float = 0
        for (fraction, duration) in zip(fractions, durations) {
            let f = min(max(fraction, previous), 1)
            let slice = path.slice(from: previous, to: f)
            out.append(slice.isEmpty ? nil
                : (nodeIndex, slice.map { player($0.x, $0.z) }, duration))
            previous = f
        }
        return out
    }

    /// Constant-speed schedule: fractions proportional to elapsed step time.
    private static func uniformFractions(_ durations: [TimeInterval]) -> [Float] {
        let total = durations.reduce(0, +)
        guard total > 0 else { return durations.map { _ in 1 } }
        var elapsed: TimeInterval = 0
        return durations.map { elapsed += $0; return Float(elapsed / total) }
    }

    /// One snap's defensive assignments derived from the dialed package.
    private struct DefensePlan {
        /// defRole → offRole he mirrors in man coverage.
        var man: [Int: Int] = [:]
        /// defRole → zone landmark (x, depth past the LOS).
        var zones: [Int: (x: Float, depth: Float)] = [:]
        /// Defense roles joining the rush beyond the front four.
        var blitzers: [Int] = []
    }

    /// The defense plays its CALL: Man Press/Free/2-Man and Cover 1 lock men
    /// (CB↔WR role mapping shared with `MatchupResolver.coverFor`), zone
    /// shells drop to their landmarks (Cover 2 squats the corners in the
    /// flats with two deep halves, Cover 3 three deep thirds, Quarters four
    /// deep, Prevent a sky-high shell), and blitz packages send the spec'd
    /// extra men (Double A-Gap both backers inside, safety/corner heat off
    /// the edge).
    private static func defensePlan(_ c: Context) -> DefensePlan {
        var plan = DefensePlan()
        switch c.package?.blitz {
        case .lbBlitz:     plan.blitzers = [4]
        case .doubleAGap:  plan.blitzers = [4, 5]
        case .safetyBlitz: plan.blitzers = [10]
        case .dbBlitz:     plan.blitzers = [10]
        case .allOutBlitz: plan.blitzers = [4, 5, 6, 10]
        default: break
        }
        switch c.package?.coverage {
        case .manToMan:
            plan.man = [7: 7, 8: 8, 9: 9, 5: 10, 6: 1]
            plan.zones = [4: (-2, 5), 10: (5, 13)]
        case .cover1:
            // Man free: tight man underneath, a single-high net over the top.
            plan.man = [7: 7, 8: 8, 9: 9, 5: 10, 6: 1]
            plan.zones = [4: (-2, 5), 10: (0, 16)]
        case .cover2:
            plan.zones = [7: (-13, 5), 8: (13, 5), 9: (-9, 15), 10: (9, 15),
                          4: (-8, 7), 5: (0, 10), 6: (8, 7)]
        case .cover4:
            plan.zones = [7: (-13, 14), 8: (13, 14), 9: (-5, 14), 10: (5, 14),
                          4: (-7, 6), 5: (0, 6.5), 6: (7, 6)]
        case .prevent:
            plan.zones = [7: (-13, 17), 8: (13, 17), 9: (-5, 19), 10: (5, 19),
                          4: (-8, 8), 5: (0, 9), 6: (8, 8)]
        default:
            // Cover 3 shell for the base call and undialed defenses.
            plan.zones = [7: (-12, 15), 8: (12, 15), 9: (0, 16), 10: (9, 6),
                          4: (-8, 5.5), 5: (0, 6.5), 6: (4.5, 5.5)]
        }
        for role in plan.blitzers {
            plan.man.removeValue(forKey: role)
            plan.zones.removeValue(forKey: role)
        }
        return plan
    }

    /// Trail distance a defender concedes to a receiver, read from the
    /// play's matchup events: a route winner uncovers ~1.5yd, a loser is
    /// blanketed at ~0.3yd, and the target uses the sim's separation number.
    private static func trailYards(offRole: Int, c: Context) -> Float {
        guard let m = c.matchups else { return 0.8 }
        if m.openNonTargetOffRole == offRole { return 1.7 }
        if m.targetOffRole == offRole { return Float(min(max(m.separation, 0.3), 2.5)) }
        for event in m.events where event.offRole == offRole && event.defRole != nil {
            return event.offenseWon ? 1.5 : 0.3
        }
        return 0.8
    }

    /// Man-coverage mirror: the defender runs his receiver's route shape,
    /// closing from his pre-snap cushion into `trail` yards behind the man.
    private static func mirrorPath(_ route: RoutePath, defenderStart: (x: Float, z: Float),
                                   trail: Float, direction: Float) -> RoutePath {
        guard route.pts.count > 1 else { return RoutePath(points: [defenderStart]) }
        var points = [defenderStart]
        let startLag = (defenderStart.z - route.pts[0].z) * direction
        let xOffset = min(max(defenderStart.x - route.pts[0].x, -1.2), 1.2)
        let count = Float(route.pts.count - 1)
        for (index, point) in route.pts.enumerated().dropFirst() {
            let t = Float(index) / count
            let lag = startLag * (1 - t) * (1 - t) - trail * t
            points.append((clampX(point.x + xOffset * (1 - t)),
                           clampZ(point.z + direction * lag)))
        }
        return RoutePath(points: points)
    }

    /// Zone defenders sink toward their landmarks (`p` grows across steps).
    private static func zoneMoves(_ c: Context, plan: DefensePlan, p: Float,
                                  exclude: Set<Int> = [], d: TimeInterval) -> [Move] {
        plan.zones.compactMap { role, landmark in
            let idx = c.dBase + role
            guard !exclude.contains(idx) else { return nil }
            let start = c.defense[role]
            return (idx, player(lerp(start.x, landmark.x, p),
                                lerp(start.z, c.losZ + c.direction * landmark.depth, p)), d)
        }
    }

    /// A blitzer's rush lane: through his spec'd gap at the LOS, then on to
    /// the QB's depth. Double A-Gap sends both backers inside the center;
    /// safety/corner pressure bends around the edge.
    private static func blitzPath(role: Int, c: Context, qbDropZ: Float) -> RoutePath {
        let start = c.defenseStart(role)
        let gapX: Float
        if c.package?.blitz == .doubleAGap && (role == 4 || role == 5) {
            gapX = role == 4 ? -1.0 : 1.0
        } else if role >= 9 {
            gapX = start.x < 0 ? -5.5 : 5.5
        } else {
            gapX = start.x * 0.5
        }
        return RoutePath(points: [
            (start.x, start.z),
            (clampX(gapX), clampZ(c.losZ - c.direction * 0.3)),
            (clampX(gapX * 0.3), clampZ(qbDropZ + c.direction * 1.2)),
        ])
    }

    /// Everything shared by the dropback scripts, precomputed per play:
    /// step durations, every route runner's per-step path slices, man
    /// mirrors, zone drops and blitz lanes. Frame steps: 0 snap, 1 drop,
    /// 2 throw/flight.
    private struct DropbackFrame {
        var durations: [TimeInterval]
        var qbDrop: SCNVector3
        /// offense role → per-step path moves.
        var routeSlices: [Int: [PathMove?]]
        /// defense role → per-step path moves (man mirrors + blitz lanes).
        var defenseSlices: [Int: [PathMove?]]
        var plan: DefensePlan
        /// The defender locked on the target in man coverage, if any.
        var manOnTarget: Int?
        /// True when the back stays in to block (no spec route for him).
        var rbBlocks: Bool
        /// offense role → where his route ends (post-catch jog anchors).
        var routeEnds: [Int: (x: Float, z: Float)] = [:]
    }

    private static func dropbackFrame(_ c: Context, targetRole: Int?,
                                      targetPath: RoutePath?,
                                      durations: [TimeInterval],
                                      qbDropZ: Float) -> DropbackFrame {
        var plan = defensePlan(c)
        let uniform = uniformFractions(durations)

        // Route runners: the target on his fitted path, everyone else runs
        // his FULL spec route for the whole play.
        var routes: [Int: RoutePath] = [:]
        for role in [1, 7, 8, 9, 10] {
            if role == targetRole, let targetPath {
                routes[role] = targetPath
            } else if let path = specPath(role: role, c: c) {
                routes[role] = path
            } else if role == targetRole {
                routes[role] = fallbackPath(role: role, c: c)
            }
        }
        // The target's timing stays synced to the ball (uniform schedule);
        // every other runner covers his route at HIS OWN attribute speed —
        // fast men clear early, plodders are still stemming at the throw.
        var routeFractions: [Int: [Float]] = [:]
        var routeSlices: [Int: [PathMove?]] = [:]
        var routeEnds: [Int: (x: Float, z: Float)] = [:]
        for (role, path) in routes {
            let fractions = role == targetRole
                ? uniform
                : speedFractions(durations, total: path.total, speed: c.oSpeed(role))
            routeFractions[role] = fractions
            routeEnds[role] = path.end
            routeSlices[role] = pathMoves(path, nodeIndex: c.oBase + role,
                                          fractions: fractions, durations: durations)
        }

        // Man mirrors trail their men (phase-locked to the man's schedule so
        // the trail distance stays honest); a man defender whose man stayed
        // in to block falls into a hook zone instead.
        var defenseSlices: [Int: [PathMove?]] = [:]
        var manOnTarget: Int?
        for (defRole, offRole) in plan.man {
            guard let route = routes[offRole] else {
                let start = c.defenseStart(defRole)
                plan.zones[defRole] = (start.x * 0.4, 4.5)
                continue
            }
            if offRole == targetRole { manOnTarget = defRole }
            let mirror = mirrorPath(route, defenderStart: c.defenseStart(defRole),
                                    trail: trailYards(offRole: offRole, c: c),
                                    direction: c.direction)
            defenseSlices[defRole] = pathMoves(mirror, nodeIndex: c.dBase + defRole,
                                               fractions: routeFractions[offRole] ?? uniform,
                                               durations: durations)
        }

        // Blitzers cross the line on the snap and reach the QB by the end of
        // the drop, where the protection washes them.
        var rushFractions = [Float](repeating: 1, count: durations.count)
        if !rushFractions.isEmpty { rushFractions[0] = 0.55 }
        for role in plan.blitzers {
            let lane = blitzPath(role: role, c: c, qbDropZ: qbDropZ)
            defenseSlices[role] = pathMoves(lane, nodeIndex: c.dBase + role,
                                            fractions: rushFractions, durations: durations)
        }

        return DropbackFrame(durations: durations,
                             qbDrop: player(c.offenseStart(0).x, qbDropZ),
                             routeSlices: routeSlices,
                             defenseSlices: defenseSlices,
                             plan: plan,
                             manOnTarget: manOnTarget,
                             rbBlocks: routes[1] == nil,
                             routeEnds: routeEnds)
    }

    /// All route/coverage/blitz path moves for one step of the frame.
    private static func framePaths(_ frame: DropbackFrame, step: Int,
                                   excludeNodes: Set<Int> = []) -> [PathMove] {
        var out: [PathMove] = []
        for slices in frame.routeSlices.values {
            if step < slices.count, let move = slices[step],
               !excludeNodes.contains(move.nodeIndex) {
                out.append(move)
            }
        }
        for slices in frame.defenseSlices.values {
            if step < slices.count, let move = slices[step],
               !excludeNodes.contains(move.nodeIndex) {
                out.append(move)
            }
        }
        return out
    }

    /// Frame step 0: the snap — pocket sets, all routes release, zones sink,
    /// blitzers show. Play action first sells the dive: the QB rides the
    /// fake, the back plunges into the line empty, and the linebackers bite
    /// downhill before recovering.
    private static func snapStep(_ c: Context, frame: DropbackFrame, isPA: Bool) -> Step {
        let d = frame.durations[0]
        var scripted: [Move] = []
        if isPA {
            let qbStart = c.offenseStart(0)
            scripted.append((c.qb, player(qbStart.x + 0.6, qbStart.z + c.direction * 0.8), d * 0.9))
            if frame.rbBlocks {
                scripted.append((c.rb, player(0.4, c.losZ + c.direction * 0.3), d))
            }
        } else if frame.rbBlocks {
            // The back scans for work at the pocket's front porch.
            let rbStart = c.offenseStart(1)
            scripted.append((c.rb, player(rbStart.x * 0.7, c.losZ - c.direction * 3.4), d))
        }
        var zone = zoneMoves(c, plan: frame.plan, p: 0.45, d: d)
        if isPA {
            zone = zone.map { move in
                let role = move.nodeIndex - c.dBase
                guard [4, 5, 6].contains(role) else { return move }
                let start = c.defense[role]
                return (move.nodeIndex, player(start.x * 0.7, c.losZ + c.direction * 2), d)
            }
        }
        let paths = framePaths(frame, step: 0)
        let taken = Set(paths.map(\.nodeIndex))
        let moves = merge(scripted, pocketMoves(c, p: 0.45, d: d) + zone)
            .filter { !taken.contains($0.nodeIndex) }
        return Step(moves: moves, paths: paths, ballMove: c.snapExchange, duration: d,
                    blocks: lineBlockNodes(c),
                    startDelays: snapReactionDelays(c))
    }

    /// Frame step 1: the dropback — the QB backpedals to depth (eyes down
    /// the field, ball in both hands at the chest), routes stem, zones keep
    /// sinking, the rush pushes the pocket. `pumpFake` sells a deep-shot
    /// pump at the top of the drop (~30% of deep throws).
    private static func dropStep(_ c: Context, frame: DropbackFrame,
                                 pumpFake: Bool = false) -> Step {
        let d = frame.durations[1]
        let paths = framePaths(frame, step: 1)
        let taken = Set(paths.map(\.nodeIndex))
        let moves = merge([(nodeIndex: c.qb, to: frame.qbDrop, duration: d)],
                          pocketMoves(c, p: 1, d: d)
                              + zoneMoves(c, plan: frame.plan, p: 0.9, d: d))
            .filter { !taken.contains($0.nodeIndex) }
        return Step(moves: moves, paths: paths, ballMove: .carryChest(nodeIndex: c.qb),
                    duration: d, backpedals: [c.qb],
                    blocks: lineBlockNodes(c),
                    pumpFakes: pumpFake ? [c.qb] : [])
    }

    /// QB drop depth past his alignment: from under center he runs a real
    /// 3-step (short) or 5-step (deep) drop with crossover strides; from
    /// the gun he only settles a step or two deeper.
    private static func dropDepth(_ c: Context, deep: Bool) -> Float {
        deep ? (c.qbUnderCenter ? 4.8 : 2.5) : (c.qbUnderCenter ? 3.2 : 1.5)
    }

    /// The zone defender whose landmark sits closest to a point — he's the
    /// one who breaks on the ball while it's in the air.
    private static func nearestZoneDefender(_ plan: DefensePlan, to point: (x: Float, z: Float),
                                            c: Context) -> Int? {
        plan.zones.min { lhs, rhs in
            let ldx = lhs.value.x - point.x
            let ldz = (c.losZ + c.direction * lhs.value.depth) - point.z
            let rdx = rhs.value.x - point.x
            let rdz = (c.losZ + c.direction * rhs.value.depth) - point.z
            return ldx * ldx + ldz * ldz < rdx * rdx + rdz * rdz
        }?.key
    }

    /// Fits a run track's spec shape to the simulated end spot: the shape is
    /// followed until it would pass the tackle depth (cut there), extended
    /// downfield when the run breaks past it, or pulled back for a stuff.
    private static func fitTrack(_ shape: RoutePath, endZ: Float, direction: Float) -> RoutePath {
        var out: [(x: Float, z: Float)] = [shape.pts[0]]
        for index in 1..<shape.pts.count {
            let a = out[out.count - 1]
            let b = shape.pts[index]
            if (b.z - a.z) * direction > 0.01,
               (endZ - a.z) * direction >= 0, (b.z - endZ) * direction >= 0 {
                let t = (endZ - a.z) / (b.z - a.z)
                out.append((a.x + (b.x - a.x) * t, endZ))
                return RoutePath(points: out)
            }
            out.append(b)
        }
        let last = out[out.count - 1]
        if (endZ - last.z) * direction > 0.2 {
            out.append((clampX(last.x + (last.x <= 0 ? 1.5 : -1.5)), endZ))
        } else if (last.z - endZ) * direction > 0.2 {
            out.append((last.x, endZ))
        }
        return RoutePath(points: out)
    }

    /// Splices a hard lateral jig into a run track at an arc-length fraction
    /// — the path half of a juke (the scheduled body feint sells the rest).
    private static func jig(_ path: RoutePath, at fraction: Float, side: Float) -> RoutePath {
        guard path.pts.count >= 2 else { return path }
        var points = [path.pts[0]] + path.slice(from: 0, to: fraction)
        let base = path.point(at: fraction)
        let ahead = path.point(at: min(fraction + 0.1, 1))
        points.append((clampX(base.x + side * 1.6),
                       clampZ(base.z + (ahead.z - base.z) * 0.5)))
        points += path.slice(from: min(fraction + 0.16, 1), to: 1)
        return RoutePath(points: points)
    }

    // MARK: - Scripts: Runs

    /// Snap → handoff → the carrier follows his CALL's spec track fitted to
    /// the simulated end spot (dive straight downhill, sweep/toss arcing
    /// wide, counter jabbing away before the cutback, jet sweep behind
    /// pre-snap motion, draw off a sold dropback) with converging defenders
    /// → tackle. The matchup layer still shades the trench visuals, and a
    /// QB scramble keeps the ball with the QB.
    /// Returns the carrier and end spot so touchdown/fumble scripts can extend it.
    private static func rushSteps(_ c: Context, endZ: Float, includeTackle: Bool = true)
        -> (steps: [Step], carrier: Int, end: SCNVector3, tackler: Int) {
        let qbStart = c.offenseStart(0)
        // QB keeper when the sim named him — or, with no sim attribution
        // (two-point tries), when the call itself is his (sneak).
        let isScramble = c.carrierRole == 0
            || (c.carrierRole == nil && c.spec.carrierRole == 0)
        let carrierRole = isScramble ? 0 : 1
        let carrier = c.oBase + carrierRole
        let carrierStart = c.offenseStart(carrierRole)
        let isDraw = c.call == .draw
        let isJet = c.call == .jetSweep
        let isToss = c.call == .toss
        // A scramble off a called PASS (the spec has no QB track): the QB
        // panics out of a collapsing pocket — a drop, a sharp escape to one
        // side, then he turns it upfield. The whole play sells pass first.
        let panicScramble = isScramble && c.spec.routes[0] == nil
        // Everything that shows a dropback look before the run.
        let sellsPass = isDraw || panicScramble
        // A gaping hole (holeSize 1) blows the DL a yard past the LOS; a
        // stuffed front (0) lets it penetrate into the backfield instead.
        let surgeShift = (c.holeSize - 0.4) * 2.2

        // The carrier's track: the call's spec shape fitted to the sim's end.
        let shape: RoutePath
        if panicScramble {
            let side: Float = Bool.random() ? 1 : -1
            shape = RoutePath(points: [
                (carrierStart.x, carrierStart.z),
                (carrierStart.x + side * 0.7, carrierStart.z - c.direction * 2.4),
                (carrierStart.x + side * 4.2, carrierStart.z - c.direction * 1.2),
                (clampX(carrierStart.x + side * 6.0), c.losZ + c.direction * 1.5),
            ])
        } else {
            shape = specPath(role: carrierRole, c: c)
                ?? RoutePath(points: [(carrierStart.x, carrierStart.z),
                                      (clampX(carrierStart.x + (carrierStart.x <= 0 ? 2 : -2)), endZ)])
        }
        var track = fitTrack(shape, endZ: endZ, direction: c.direction)

        // Handoff timing along the track: the mesh lands ~a third in; the
        // delayed draw holds the back until the dropback is sold.
        let f1: Float = isDraw ? 0.06 : 0.14
        let f2: Float = isDraw ? 0.3 : (isScramble ? 0.42 : 0.32)

        // Breakaway runs flash 1-2 open-field moves; a juke also splices a
        // hard lateral jig into the track so the cut is real, not just a
        // body feint. Matchup winners show off more often.
        let runGain = (endZ - c.losZ) * c.direction
        var openFieldPlan: [(kind: FootballFieldScene.OpenFieldMove.Kind, fraction: Float)] = []
        if runGain >= 12 {
            let carrierWon = c.matchups?.events
                .contains { $0.offenseWon && $0.offRole == carrierRole } ?? false
            let two = runGain >= 22 || (carrierWon && Bool.random())
            let kinds: [FootballFieldScene.OpenFieldMove.Kind] = [.juke, .spin, .stiffArm].shuffled()
            let beats: [Float] = two ? [0.55, 0.82] : [0.62]
            for (index, fraction) in beats.enumerated() {
                let kind = kinds[index]
                if kind == .juke {
                    track = jig(track, at: fraction, side: Bool.random() ? 1 : -1)
                }
                openFieldPlan.append((kind, fraction))
            }
        }
        let end = player(track.end.x, track.end.z)
        let endX = end.x

        let snapDur: TimeInterval = isDraw ? 0.95 : (panicScramble ? 0.8 : 0.65)
        let meshDur: TimeInterval = 0.55
        // The open-field leg is covered at the CARRIER's attribute speed —
        // a 4.4 burner outruns the pursuit, a plodding back gets swallowed.
        let carrierSpeed = c.oSpeed(carrierRole)
        let runDur = TimeInterval(min(max(Double(track.total * (1 - f2)) / Double(carrierSpeed), 0.9), 3.4))
        let durations = [snapDur, meshDur, runDur]
        let carrierSlices = pathMoves(track, nodeIndex: carrier,
                                      fractions: [f1, f2, 1], durations: durations)
        // Open-field beats land inside the run step (fractions past f2).
        let openFieldMoves: [FootballFieldScene.OpenFieldMove] = openFieldPlan.map { plan in
            FootballFieldScene.OpenFieldMove(
                nodeIndex: carrier, kind: plan.kind,
                delay: runDur * TimeInterval(max((plan.fraction - f2) / max(1 - f2, 0.01), 0.05)))
        }

        var steps: [Step] = []
        var stalkExclude: Set<Int> = [carrier]

        // 0. Jet sweep: the slot flies across the formation BEFORE the snap
        //    (ball doesn't move); the sweep then chases his motion.
        if isJet, let motionRole = c.spec.motionRole,
           let motionPath = specPath(role: motionRole, c: c) {
            stalkExclude.insert(c.oBase + motionRole)
            steps.append(Step(
                moves: [(c.oBase + motionRole, player(motionPath.end.x, motionPath.end.z), 0.9)],
                ballMove: nil,
                duration: 0.95
            ))
        }

        // A pass-selling run (draw/scramble) sends the receivers on their
        // real routes across all three steps while the line shows a pocket.
        let plan = defensePlan(c)
        var clearSlices: [PathMove?] = []
        if sellsPass {
            for role in [7, 8, 9, 10] {
                guard let path = specPath(role: role, c: c) else { continue }
                stalkExclude.insert(c.oBase + role)
                clearSlices += pathMoves(
                    path, nodeIndex: c.oBase + role,
                    fractions: speedFractions(durations, total: path.total, speed: c.oSpeed(role)),
                    durations: durations)
            }
        }
        func clears(_ step: Int) -> [PathMove] {
            stride(from: step, to: clearSlices.count, by: 3).compactMap { clearSlices[$0] }
        }

        // 1. Snap: ball back to the QB; both lines fire off, the receivers
        //    release toward their stalk blocks and the back seven keys run
        //    (a draw shows pass everywhere: pocket, sinking zones, clears).
        var snapPaths = clears(0)
        if let slice = carrierSlices[0] { snapPaths.append(slice) }
        var snapScripted: [Move] = []
        var snapBackpedals: [Int] = []
        if isDraw {
            snapScripted.append((c.qb, player(qbStart.x, qbStart.z - c.direction * 1.5), snapDur))
            snapBackpedals.append(c.qb)
        }
        let snapTaken = Set(snapPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                snapScripted,
                (sellsPass
                    ? pocketMoves(c, p: 0.6, d: snapDur)
                        + zoneMoves(c, plan: plan, p: 0.5, d: snapDur)
                    : lineSurgeMoves(c, p: 0.55, d: 0.55, dlShift: surgeShift * 0.4)
                        + routeMoves(c, p: 0.3, depthScale: 0.45, exclude: stalkExclude, d: 0.55)
                        + coverageMoves(c, mode: .run, p: 0.35, d: 0.55))
            ).filter { !snapTaken.contains($0.nodeIndex) },
            paths: snapPaths,
            ballMove: c.snapExchange,
            duration: snapDur,
            backpedals: snapBackpedals,
            blocks: lineBlockNodes(c),
            startDelays: snapReactionDelays(c)
        ))

        // 2. Handoff (or the QB tucks it): the carrier hits the mesh on his
        //    track and the line battle resolves — winners visibly move the
        //    front. A toss flips the ball out to him in a little pitch arc.
        var meshPaths = clears(1)
        if let slice = carrierSlices[1] { meshPaths.append(slice) }
        let meshTaken = Set(meshPaths.map(\.nodeIndex))
        let meshBall: FootballFieldScene.BallMove = isToss
            ? .arc(to: air(track.point(at: f2).x, track.point(at: f2).z),
                   apex: 1.4, duration: meshDur * 0.85)
            : .carry(nodeIndex: carrier)
        steps.append(Step(
            moves: merge(
                [],
                (sellsPass
                    ? pocketMoves(c, p: 1, d: meshDur)
                        + zoneMoves(c, plan: plan, p: 0.8, d: meshDur)
                    : lineSurgeMoves(c, p: 1, d: 0.55, dlShift: surgeShift)
                        + routeMoves(c, p: 0.6, depthScale: 0.45, exclude: stalkExclude, d: 0.55)
                        + coverageMoves(c, mode: .run, p: 0.7, d: 0.55))
            ).filter { !meshTaken.contains($0.nodeIndex) },
            paths: meshPaths,
            ballMove: meshBall,
            duration: meshDur,
            blocks: lineBlockNodes(c)
        ))

        // 3. Run: the carrier finishes his track downfield; the credited
        //    defender leads the converge, the rest rally to the spot.
        let runDuration = runDur
        let tackler = c.defenseWinnerRole.map { c.dBase + $0 } ?? c.lb(1)
        var runPaths: [PathMove] = clears(2)
        if let slice = carrierSlices[2] { runPaths.append(slice) }
        let runTaken = Set(runPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: tackler, to: player(endX + 0.7, end.z + c.direction * 0.7), duration: runDuration),
                    (nodeIndex: c.dl(1), to: player(endX - 0.8, end.z - c.direction * 0.5), duration: runDuration),
                    (nodeIndex: endX < 0 ? c.safety(0) : c.safety(1),
                     to: player(endX, end.z + c.direction * 1.4), duration: runDuration),
                ],
                routeMoves(c, p: 1, depthScale: 0.45, exclude: stalkExclude, d: runDuration)
                    + pursuitMoves(c, toX: endX, toZ: end.z, fraction: 0.55, d: runDuration)
                    + (isScramble ? [] : trailMoves(c, toX: endX, toZ: end.z, roles: [0], fraction: 0.3, d: runDuration))
            ).filter { !runTaken.contains($0.nodeIndex) },
            paths: runPaths,
            ballMove: .carry(nodeIndex: carrier),
            duration: runDuration,
            openField: openFieldMoves
        ))

        // 4. Tackle: the hit — carrier and tackler go to the turf, and the
        //    nearest chasers dive onto the pile a beat later (falls stagger
        //    by list order) for a gang-tackle read. The tackler's arms wrap
        //    the carrier, and ~30% of hits first drive him back 0.5-1 yard.
        if includeTackle {
            steps += tackleSteps(c, carrier: carrier, tackler: tackler, x: endX, z: end.z)
        }

        return (steps, carrier, end, tackler)
    }

    /// The shared tackle finish, picked from the hit library:
    /// - BIG HIT (the defense clearly won a short play): the carrier is
    ///   blown a yard backward onto his back with a small camera pump.
    /// - DRAG-DOWN (breakaway plays): the tackler hauls the carrier down
    ///   from behind and both slide forward through the whistle.
    /// - DIVING TACKLE (a defender closing from long range): a flat
    ///   horizontal launch at the carrier's legs.
    /// - WRAP (default): stand-up wrap with an occasional 0.5-1 yard
    ///   drive-back (the Madden-2000 push tackle), gang chasers piling on.
    private static func tackleSteps(_ c: Context, carrier: Int, tackler: Int,
                                    x: Float, z: Float) -> [Step] {
        let gain = (z - c.losZ) * c.direction
        let tacklerRole = tackler - c.dBase
        let approach: Float
        if tacklerRole >= 0 && tacklerRole < 11 {
            let start = c.defense[tacklerRole]
            approach = ((start.x - x) * (start.x - x)
                + (start.z - z) * (start.z - z)).squareRoot()
        } else {
            approach = 0
        }
        let roll = Float.random(in: 0..<1)

        // Big hit: the carrier flies backward off his feet onto his back.
        if c.defenseWinnerRole != nil, gain < 3, roll < 0.35 {
            let backZ = clampZ(z - c.direction * Float.random(in: 0.9...1.3))
            let gang = gangTacklers(c, x: x, z: backZ, excluding: [tackler])
            return [Step(
                moves: [
                    (nodeIndex: carrier, to: player(x, backZ), duration: 0.3),
                    (nodeIndex: tackler, to: player(x + 0.3, backZ + c.direction * 0.7), duration: 0.3),
                ] + pileOnMoves(c, gang: gang, x: x, z: backZ),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.4,
                pulses: [tackler],
                falls: [tackler] + gang,
                bigHits: [carrier]
            )]
        }

        // Drag-down from behind on a breakaway: both slide forward together.
        if gain >= 12, roll < 0.6 {
            let slideZ = clampZ(z + c.direction * 0.9)
            let gang = gangTacklers(c, x: x, z: slideZ, excluding: [tackler])
            return [Step(
                moves: [
                    (nodeIndex: carrier, to: player(x, slideZ), duration: 0.45),
                    (nodeIndex: tackler, to: player(x + 0.25, slideZ - c.direction * 0.6), duration: 0.45),
                ] + pileOnMoves(c, gang: gang, x: x, z: slideZ),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.4,
                pulses: [tackler],
                falls: [carrier, tackler] + gang,
                wraps: [tackler]
            )]
        }

        // Diving tackle: the tackler closed from distance — a flat launch
        // at the carrier's legs cuts him down.
        if approach > 12, roll < 0.7 {
            let gang = gangTacklers(c, x: x, z: z, excluding: [tackler])
            return [Step(
                moves: [(nodeIndex: tackler,
                         to: player(x + 0.3, z - c.direction * 0.4), duration: 0.25)]
                    + pileOnMoves(c, gang: gang, x: x, z: z),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.3,
                pulses: [tackler],
                falls: [carrier] + gang,
                diveFalls: [tackler]
            )]
        }

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
                 ballMove: c.snapExchange, duration: 0.6,
                 startDelays: snapReactionDelays(c)),
            Step(
                moves: [(nodeIndex: c.qb, to: player(qbStart.x, qbStart.z - c.direction * 1), duration: 0.8)],
                ballMove: .carry(nodeIndex: c.qb),
                duration: 0.8
            ),
            Step(moves: [], ballMove: .carry(nodeIndex: c.qb), duration: 0.6),
        ]
    }

    // MARK: - Scripts: Passes

    /// The sim's named target (when he's an eligible on the field), else the
    /// design's primary read.
    private static func targetRole(_ c: Context) -> Int {
        if let role = c.carrierRole, [1, 7, 8, 9, 10].contains(role) { return role }
        return c.spec.primaryRole == 0 ? 7 : c.spec.primaryRole
    }

    /// Snap → every eligible runs his FULL spec route while the pocket forms
    /// and the defense plays its call → the ball arcs to the catch point ON
    /// the target's route at the simulated depth → YAC to the sim's end spot
    /// with the beaten/blanketing defender trailing accordingly → tackle.
    private static func completionSteps(_ c: Context, endZ: Float, includeTackle: Bool = true)
        -> (steps: [Step], carrier: Int, end: SCNVector3, defender: Int) {
        if c.call == .screen {
            return screenSteps(c, endZ: endZ, complete: true, includeTackle: includeTackle)
        }
        let receiverRole = targetRole(c)
        let receiver = c.oBase + receiverRole

        // Catch point ON the target's spec route at the simulated depth:
        // estimate the air yards (total minus a modest YAC share), scale the
        // route gently toward that depth, then take the nearest point on it.
        let gainDepth = (endZ - c.losZ) * c.direction
        let rawRoute = specPath(role: receiverRole, c: c) ?? fallbackPath(role: receiverRole, c: c)
        let routeDepth = max(rawRoute.maxDepth(losZ: c.losZ, direction: c.direction), 1)
        // Blanket coverage strangles the YAC — the contested ball is caught
        // (or dived on) right about where the sim says the play died.
        let tightCoverage = c.separation < 0.7
        let yacShare = min(max(gainDepth * 0.3, 1), tightCoverage ? 1.5 : 6)
        let airDepth = max(min(gainDepth - yacShare, routeDepth * 1.2), min(1.5, gainDepth))
        let scale = min(max(airDepth / routeDepth, 0.85), 1.2)
        let scaled = specPath(role: receiverRole, c: c, depthScale: scale)
            ?? fallbackPath(role: receiverRole, c: c, depthScale: scale)
        let catchFraction = max(scaled.fractionNearest(z: c.losZ + c.direction * airDepth), 0.12)
        let targetPath = scaled.prefix(to: catchFraction)
        let catchSpot = targetPath.end
        let catchDepth = (catchSpot.z - c.losZ) * c.direction

        let isPA = c.call == .playActionDeep
        let deepDrop = airDepth >= 15
        let qbStart = c.offenseStart(0)
        let qbDropZ = clampZ(qbStart.z - c.direction * dropDepth(c, deep: deepDrop))
        // Physical pacing: the drop takes a real 1.25-1.6 s and the ball
        // flies at ~18 yd/s from the launch point (20 air yards ≈ 1.1 s).
        let throwDX = catchSpot.x - qbStart.x
        let throwDZ = catchSpot.z - qbDropZ
        let throwDistance = (throwDX * throwDX + throwDZ * throwDZ).squareRoot()
        let flight = TimeInterval(min(max(throwDistance / Self.passVelocity, 0.5), 1.5))
        let durations: [TimeInterval] = [isPA ? 1.0 : 0.65, deepDrop ? 1.6 : 1.25, flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: targetPath,
                                  durations: durations, qbDropZ: qbDropZ)

        var steps: [Step] = []

        // 1-2. Snap and dropback: all five patterns release and stem, the
        //      coverage plays its call, the rush pushes the pocket. Deep
        //      shots pump-fake at the top of the drop ~30% of the time.
        steps.append(snapStep(c, frame: frame, isPA: isPA))
        steps.append(dropStep(c, frame: frame,
                              pumpFake: deepDrop && Float.random(in: 0..<1) < 0.3))

        // 3. Throw: the ball arcs to the catch point on the route while
        //    every other pattern and coverage path plays out underneath it;
        //    the nearest zone defender breaks on the ball in the air.
        let breaker = nearestZoneDefender(frame.plan, to: catchSpot, c: c)
        let apex = 3 + min(max(catchDepth, 0), 25) / 25 * 3
        let flightPaths = framePaths(frame, step: 2)
        var flightMoves = zoneMoves(c, plan: frame.plan, p: 1,
                                    exclude: breaker.map { Set([c.dBase + $0]) } ?? [],
                                    d: flight)
        if let breaker {
            let side: Float = c.defense[breaker].x > catchSpot.x ? 1 : -1
            flightMoves.append((c.dBase + breaker,
                                player(catchSpot.x + side * 0.9, catchSpot.z + c.direction * 0.4),
                                flight))
        }
        let tacklerRole = frame.manOnTarget ?? breaker ?? (catchSpot.x < 0 ? 7 : 8)
        let db = c.dBase + tacklerRole
        let yacDistance = abs(endZ - catchSpot.z)
        // Catch presentation: toe-tap at the boundary, a layout dive under
        // blanket coverage when the sim allowed almost nothing after the
        // catch, over-the-shoulder tracking on deep balls, hands otherwise.
        let catchStyle: FootballFieldScene.CatchStyle
        if abs(catchSpot.x) >= 23 {
            catchStyle = .toeTap
        } else if includeTackle && tightCoverage && yacDistance < 2.5 {
            catchStyle = .dive
        } else if catchDepth >= 16 {
            catchStyle = .overShoulder
        } else {
            catchStyle = .reach
        }
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: flightMoves.filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: air(catchSpot.x, catchSpot.z), apex: apex, duration: flight),
            duration: flight,
            reaches: [receiver],
            catchStyles: [receiver: catchStyle]
        ))

        let openHands: [Int] = c.matchups?.openNonTargetOffRole
            .flatMap { $0 != receiverRole ? [c.oBase + $0] : nil } ?? []

        // A diving grab ends the play at the catch: the receiver is
        // stretched out on the turf with the ball, so the defense arrives
        // onto a dead pile — no run after the catch.
        if catchStyle == .dive {
            let gang = gangTacklers(c, x: catchSpot.x, z: catchSpot.z, excluding: [db])
            steps.append(Step(
                moves: merge(
                    [(nodeIndex: db,
                      to: player(catchSpot.x + 0.7, catchSpot.z + c.direction * 0.5),
                      duration: 0.5)]
                        + pileOnMoves(c, gang: gang, x: catchSpot.x, z: catchSpot.z),
                    pursuitMoves(c, toX: catchSpot.x, toZ: catchSpot.z, fraction: 0.4,
                                 exclude: [db], d: 1.0)
                ),
                ballMove: .carry(nodeIndex: receiver),
                duration: 1.6,
                falls: gang,
                reaches: openHands
            ))
            return (steps, receiver, player(catchSpot.x, catchSpot.z), db)
        }

        // 4. Run after catch: from the catch point on the route to the sim's
        //    end spot; the covering man trails by the separation he conceded
        //    — a beaten defender is visibly behind, blanket coverage arrives
        //    with the ball. An uncovered non-target who won his route throws
        //    his hands up: the QB may have missed him. A breakaway catch-and-
        //    run flashes an open-field move mid-runway.
        let endX = clampX(catchSpot.x + (catchSpot.x <= 0 ? 1.5 : -1.5))
        let end = player(endX, endZ)
        // YAC runway covered at the receiver's own attribute speed.
        let yacDuration = TimeInterval(min(max(yacDistance / c.oSpeed(receiverRole), 0.5), 2.4))
        let trail = 0.6 - c.separation * 0.8
        // Receivers whose routes are done turn to the ball and jog toward
        // the runway (YAC support) instead of standing at their route ends.
        var yacSupport: [Move] = []
        for role in [1, 7, 8, 9, 10] where role != receiverRole {
            guard let from = frame.routeEnds[role] else { continue }
            yacSupport.append((c.oBase + role,
                               player(lerp(from.x, endX, 0.35), lerp(from.z, endZ, 0.35)),
                               yacDuration))
        }
        var yacOpenField: [FootballFieldScene.OpenFieldMove] = []
        if yacDistance >= 12 {
            let kinds: [FootballFieldScene.OpenFieldMove.Kind] = [.juke, .spin, .stiffArm]
            yacOpenField.append(.init(nodeIndex: receiver,
                                      kind: kinds.randomElement() ?? .spin,
                                      delay: yacDuration * 0.4))
        }
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: receiver, to: end, duration: yacDuration),
                    (nodeIndex: db, to: player(endX + 0.7, endZ + c.direction * trail), duration: yacDuration),
                    (nodeIndex: catchSpot.x < 0 ? c.safety(0) : c.safety(1),
                     to: player(endX - 0.6, endZ + c.direction * 1.2), duration: yacDuration),
                ],
                pursuitMoves(c, toX: endX, toZ: endZ, fraction: 0.5, d: yacDuration)
                    + trailMoves(c, toX: endX, toZ: endZ, roles: [0], fraction: 0.25, d: yacDuration)
                    + yacSupport
            ),
            ballMove: .carry(nodeIndex: receiver),
            duration: yacDuration,
            reaches: openHands,
            openField: yacOpenField
        ))

        // 5. Tackle: receiver is brought down by the DB — wrap-up arms, an
        //    occasional drive-back, and the nearest chasers piling on late
        //    (staggered falls) for the gang-tackle read.
        if includeTackle {
            steps += tackleSteps(c, carrier: receiver, tackler: db, x: endX, z: endZ)
        }

        return (steps, receiver, end, db)
    }

    /// Screen: the QB drops and WAITS while the rush is let through, the
    /// interior linemen leak out in front, and the target catches it BEHIND
    /// the line before turning upfield behind the convoy.
    private static func screenSteps(_ c: Context, endZ: Float, complete: Bool,
                                    includeTackle: Bool = true)
        -> (steps: [Step], carrier: Int, end: SCNVector3, defender: Int) {
        var plan = defensePlan(c)
        let qbStart = c.offenseStart(0)
        let screenRole = targetRole(c)
        let screenIdx = c.oBase + screenRole
        let recStart = c.offenseStart(screenRole)
        let side: Float = recStart.x < 0 ? -1 : 1
        let screenSpot = player(clampX(screenRole == 1 ? recStart.x + side * 5 : recStart.x * 0.85),
                                c.losZ - c.direction * 1.6)

        let durations: [TimeInterval] = [0.7, 0.9]
        let fractions = uniformFractions(durations)

        // The target leaks behind the line; the other wideouts clear the lid.
        var routes: [Int: RoutePath] = [
            screenRole: RoutePath(points: [
                (recStart.x, recStart.z),
                (clampX(recStart.x + side * 2.5), clampZ(c.losZ - c.direction * 3.2)),
                (screenSpot.x, screenSpot.z),
            ]),
        ]
        for role in [1, 7, 8, 9] where role != screenRole {
            if let path = specPath(role: role, c: c) { routes[role] = path }
        }
        var slices: [Int: [PathMove?]] = [:]
        for (role, path) in routes {
            slices[role] = pathMoves(path, nodeIndex: c.oBase + role,
                                     fractions: fractions, durations: durations)
        }
        // Man defenders chase their men (that's what makes screens work);
        // an unoccupied man defender squats in a hook.
        var defSlices: [Int: [PathMove?]] = [:]
        for (defRole, offRole) in plan.man {
            guard let route = routes[offRole] else {
                let start = c.defenseStart(defRole)
                plan.zones[defRole] = (start.x * 0.4, 4.5)
                continue
            }
            let mirror = mirrorPath(route, defenderStart: c.defenseStart(defRole),
                                    trail: trailYards(offRole: offRole, c: c),
                                    direction: c.direction)
            defSlices[defRole] = pathMoves(mirror, nodeIndex: c.dBase + defRole,
                                           fractions: fractions, durations: durations)
        }
        func stepPaths(_ step: Int) -> [PathMove] {
            (Array(slices.values) + Array(defSlices.values))
                .compactMap { step < $0.count ? $0[step] : nil }
        }

        var steps: [Step] = []

        // 1. Snap: the QB drops deep and holds — the rush is INVITED through
        //    while the line shows a soft pass set.
        var snapMoves: [Move] = [(c.qb, player(qbStart.x, qbStart.z - c.direction * 2), durations[0])]
        for i in 0..<4 {
            let start = c.defense[i]
            snapMoves.append((c.dl(i),
                              player(start.x * 0.7, lerp(start.z, qbStart.z - c.direction * 0.5, 0.55)),
                              durations[0]))
        }
        for i in 0..<5 {
            let start = c.offense[2 + i]
            snapMoves.append((c.oBase + 2 + i, player(start.x, c.losZ - c.direction * 1.4), durations[0]))
        }
        snapMoves += zoneMoves(c, plan: plan, p: 0.4, d: durations[0])
        let snapTaken = Set(stepPaths(0).map(\.nodeIndex))
        steps.append(Step(
            moves: snapMoves.filter { !snapTaken.contains($0.nodeIndex) },
            paths: stepPaths(0),
            ballMove: c.snapExchange,
            duration: durations[0],
            backpedals: [c.qb],
            startDelays: snapReactionDelays(c)
        ))

        // 2. The trap springs: rushers close on the QB while the interior
        //    linemen leak downfield to build the convoy.
        let convoy: [(Int, SCNVector3)] = [
            (c.oBase + 3, player(screenSpot.x - side * 1.5, c.losZ + c.direction * 1.5)),
            (c.oBase + 4, player(screenSpot.x, c.losZ + c.direction * 3)),
            (c.oBase + 5, player(screenSpot.x + side * 1.5, c.losZ + c.direction * 0.5)),
        ]
        var springMoves: [Move] = [(c.qb, player(qbStart.x, qbStart.z - c.direction * 3.2), durations[1])]
        for i in 0..<4 {
            springMoves.append((c.dl(i),
                                player(qbStart.x + Float(i - 1) * 1.2 - 0.6,
                                       qbStart.z - c.direction * 2),
                                durations[1]))
        }
        for (idx, spot) in convoy { springMoves.append((idx, spot, durations[1])) }
        springMoves += zoneMoves(c, plan: plan, p: 0.8, d: durations[1])
        let springTaken = Set(stepPaths(1).map(\.nodeIndex))
        steps.append(Step(
            moves: springMoves.filter { !springTaken.contains($0.nodeIndex) },
            paths: stepPaths(1),
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: durations[1],
            backpedals: [c.qb]
        ))

        // 3. The soft toss over the rush to the screen spot behind the line.
        let tackler = plan.man.first(where: { $0.value == screenRole })?.key ?? 5
        let db = c.dBase + tackler
        if !complete {
            // Throw into the turf at his feet — dead ball, everyone pulls up.
            steps.append(Step(
                moves: [],
                ballMove: .arc(to: ground(screenSpot.x, screenSpot.z), apex: 1.6, duration: 0.5),
                duration: 0.6,
                reaches: [screenIdx]
            ))
            steps.append(Step(
                moves: [],
                ballMove: .slide(to: ground(screenSpot.x + side, screenSpot.z - c.direction * 0.8),
                                 duration: 0.45),
                duration: 0.9
            ))
            return (steps, screenIdx, screenSpot, db)
        }
        steps.append(Step(
            moves: [],
            ballMove: .arc(to: air(screenSpot.x, screenSpot.z), apex: 1.8, duration: 0.5),
            duration: 0.5,
            reaches: [screenIdx]
        ))

        // 4. YAC behind the convoy: the catch is behind the LOS and the
        //    runway is the sim's yardage — blockers escort, defense rallies.
        let endX = clampX(screenSpot.x + side * 1.5)
        let end = player(endX, endZ)
        // The screen runway is covered at the catcher's attribute speed.
        let yacDuration = TimeInterval(min(max(abs(endZ - screenSpot.z) / c.oSpeed(screenRole), 0.8), 2.6))
        let runway = RoutePath(points: [
            (screenSpot.x, screenSpot.z),
            (clampX(screenSpot.x + side * 1.2), clampZ(c.losZ + c.direction * 2)),
            (endX, endZ),
        ])
        var yacMoves: [Move] = [
            (db, player(endX + 0.7, endZ + c.direction * 0.4), yacDuration),
        ]
        for (offset, (idx, spot)) in convoy.enumerated() {
            yacMoves.append((idx,
                             player(lerp(spot.x, endX + Float(offset - 1) * 1.6, 0.6),
                                    lerp(spot.z, endZ - c.direction * 1.2, 0.6)),
                             yacDuration))
        }
        yacMoves += pursuitMoves(c, toX: endX, toZ: endZ, fraction: 0.55,
                                 exclude: [db], d: yacDuration)
        steps.append(Step(
            moves: yacMoves,
            paths: [(screenIdx, runway.slice(from: 0, to: 1).map { player($0.x, $0.z) }, yacDuration)],
            ballMove: .carry(nodeIndex: screenIdx),
            duration: yacDuration
        ))

        // 5. Tackle.
        if includeTackle {
            steps += tackleSteps(c, carrier: screenIdx, tackler: db, x: endX, z: endZ)
        }
        return (steps, screenIdx, end, db)
    }

    /// Same as a completion until the throw — every route still runs FULL,
    /// but the ball sails past the target's break and slides dead; he lunges
    /// and comes up empty. If a non-target was clearly open, he throws his
    /// hands up over the dead ball.
    private static func incompletionSteps(_ c: Context) -> [Step] {
        if c.call == .screen {
            return screenSteps(c, endZ: c.losZ, complete: false).steps
        }
        let receiverRole = targetRole(c)
        let receiver = c.oBase + receiverRole

        let route = specPath(role: receiverRole, c: c) ?? fallbackPath(role: receiverRole, c: c)
        let routeDepth = max(route.maxDepth(losZ: c.losZ, direction: c.direction), 1)

        // Overthrow: 1.5yd beyond the route's end, along its final leg.
        let endPt = route.end
        let prevPt = route.pts.count >= 2 ? route.pts[route.pts.count - 2]
            : (x: endPt.x, z: endPt.z - c.direction)
        let legDX = endPt.x - prevPt.x
        let legDZ = endPt.z - prevPt.z
        let legLen = max((legDX * legDX + legDZ * legDZ).squareRoot(), 0.01)
        let miss = air(clampX(endPt.x + legDX / legLen * 1.5),
                       clampZ(endPt.z + legDZ / legLen * 1.5), 0.5)

        let isPA = c.call == .playActionDeep
        let deepDrop = routeDepth >= 15
        let qbStart = c.offenseStart(0)
        let qbDropZ = clampZ(qbStart.z - c.direction * dropDepth(c, deep: deepDrop))
        // Real drop time + ball flight from the actual throw distance.
        let missDX = miss.x - qbStart.x
        let missDZ = miss.z - qbDropZ
        let missDistance = (missDX * missDX + missDZ * missDZ).squareRoot()
        let flight = TimeInterval(min(max(missDistance / Self.passVelocity, 0.55), 1.5))
        let durations: [TimeInterval] = [isPA ? 1.0 : 0.65, deepDrop ? 1.6 : 1.25, flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: route,
                                  durations: durations, qbDropZ: qbDropZ)

        var steps: [Step] = []
        steps.append(snapStep(c, frame: frame, isPA: isPA))
        steps.append(dropStep(c, frame: frame,
                              pumpFake: deepDrop && Float.random(in: 0..<1) < 0.3))

        // Overthrown ball; the target finishes his route and lunges after it
        // while every other pattern and coverage path plays out.
        var flightPaths = framePaths(frame, step: 2, excludeNodes: [receiver])
        var lungePoints = frame.routeSlices[receiverRole]?[2]?.points ?? []
        lungePoints.append(player(endPt.x + legDX / legLen * 1.0,
                                  endPt.z + legDZ / legLen * 1.0))
        flightPaths.append((receiver, lungePoints, flight))
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: zoneMoves(c, plan: frame.plan, p: 1, d: flight)
                .filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: miss, apex: 4, duration: flight),
            duration: flight,
            reaches: [receiver]
        ))

        // Ball skips dead along the turf. No advance — but a clearly open
        // non-target throws his hands up: the coach can SEE the missed read.
        let openHands: [Int] = c.matchups?.openNonTargetOffRole
            .flatMap { $0 != receiverRole ? [c.oBase + $0] : nil } ?? []
        steps.append(Step(
            moves: [],
            ballMove: .slide(to: ground(miss.x, miss.z + c.direction * 1.2), duration: 0.5),
            duration: 0.6,
            reaches: openHands
        ))
        steps.append(Step(moves: [], ballMove: nil, duration: 0.5))
        return steps
    }

    /// Snap → dropback → the CREDITED rusher beats his blocker and buries the
    /// QB at losZ - direction * |yards|. The pocket caves from the WINNING
    /// rusher's side (his blocker is driven back), routes still run full so
    /// the coach can see whether someone came open late. Ball never leaves
    /// the QB.
    private static func sackSteps(_ c: Context) -> [Step] {
        let sackDepth = max(Float(abs(c.play.yardsGained)), 2)
        let qbStart = c.offenseStart(0)
        let sackSpot = player(qbStart.x, c.losZ - c.direction * sackDepth)
        let rusherRole = c.matchups?.rushWinnerDefRole ?? 2
        let rusher = c.dl(rusherRole)
        let beaten = blockerFacing(defRole: rusherRole)
        // Real pocket time: pocketCollapse 0…1 → the rush gets home in
        // 2.3…1.4 s (a snap-to-sack of roughly 3-3.5 s with the snap step).
        let rushTime = TimeInterval(2.3 - c.pocketCollapse * 0.9)
        let durations: [TimeInterval] = [0.65, rushTime, 0.8]
        let frame = dropbackFrame(c, targetRole: nil, targetPath: nil,
                                  durations: durations, qbDropZ: sackSpot.z)

        var steps: [Step] = []

        // Snap: protection sets, all routes release, coverage plays its call.
        steps.append(snapStep(c, frame: frame, isPA: c.call == .playActionDeep))

        // Dropback (backpedal) while the credited rusher knifes through a
        // pocket collapsing from HIS side — his blocker gets driven back.
        let dropPaths = framePaths(frame, step: 1)
        var taken = Set(dropPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: c.qb, to: sackSpot, duration: rushTime),
                    (nodeIndex: rusher, to: player(sackSpot.x + 1, sackSpot.z + c.direction * 1.5), duration: rushTime),
                ],
                pocketMoves(c, p: 1, d: rushTime, beatenBlocker: beaten)
                    + zoneMoves(c, plan: frame.plan, p: 0.9, d: rushTime)
            ).filter { !taken.contains($0.nodeIndex) },
            paths: dropPaths,
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: rushTime,
            backpedals: [c.qb],
            blocks: lineBlockNodes(c).filter { $0 != rusher }
        ))

        // Rusher closes the last yard; the patterns finish with nowhere to go.
        let finishPaths = framePaths(frame, step: 2)
        taken = Set(finishPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [(nodeIndex: rusher, to: player(sackSpot.x + 0.4, sackSpot.z), duration: 0.8)],
                zoneMoves(c, plan: frame.plan, p: 1, d: 0.75)
            ).filter { !taken.contains($0.nodeIndex) },
            paths: finishPaths,
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: 0.8
        ))

        // Sack: the QB is buried; both hit the turf, the rusher wrapped
        // around him. A clearly open receiver signals what might have been.
        let openHands: [Int] = c.matchups?.openNonTargetOffRole
            .flatMap { [c.oBase + $0] } ?? []
        steps.append(Step(moves: [], ballMove: .carryChest(nodeIndex: c.qb), duration: 1.3,
                          pulses: [rusher], falls: [c.qb, rusher], wraps: [rusher],
                          reaches: openHands))
        steps.append(Step(moves: [], ballMove: .carryChest(nodeIndex: c.qb), duration: 0.4))
        return steps
    }

    /// Like a completion, but the CREDITED DB undercuts the target's route:
    /// the ball arcs to a point ON the route and he jumps it, returning ~5yd
    /// the other way. Every other pattern still runs full.
    private static func interceptionSteps(_ c: Context) -> [Step] {
        let receiverRole = targetRole(c)
        let receiver = c.oBase + receiverRole

        let route = specPath(role: receiverRole, c: c) ?? fallbackPath(role: receiverRole, c: c)
        let routeDepth = max(route.maxDepth(losZ: c.losZ, direction: c.direction), 1)

        // The pick point sits on the route, undercut a step toward the LOS.
        let pickBase = route.point(at: 0.82)
        let pick = player(pickBase.x, clampZ(pickBase.z - c.direction * 0.8))

        let isPA = c.call == .playActionDeep
        let deepDrop = routeDepth >= 15
        let qbStart = c.offenseStart(0)
        let qbDropZ = clampZ(qbStart.z - c.direction * dropDepth(c, deep: deepDrop))
        // Real drop time + ball flight from the throw distance to the pick.
        let pickDX = pick.x - qbStart.x
        let pickDZ = pick.z - qbDropZ
        let pickDistance = (pickDX * pickDX + pickDZ * pickDZ).squareRoot()
        let flight = TimeInterval(min(max(pickDistance / Self.passVelocity, 0.55), 1.5))
        let durations: [TimeInterval] = [isPA ? 1.0 : 0.65, deepDrop ? 1.6 : 1.25, flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: route,
                                  durations: durations, qbDropZ: qbDropZ)

        // The credited DB (else the man on the target, else the nearest zone
        // defender) is the one who jumps it.
        let dbRole = c.matchups?.pickDefRole
            ?? frame.manOnTarget
            ?? nearestZoneDefender(frame.plan, to: (pick.x, pick.z), c: c)
            ?? (route.pts[0].x < 0 ? 7 : 8)
        let db = c.dBase + dbRole

        var steps: [Step] = []
        steps.append(snapStep(c, frame: frame, isPA: isPA))
        steps.append(dropStep(c, frame: frame))

        // Throw sails to the undercut point: the DB drives on it while the
        // target finishes his break a step deep.
        let flightPaths = framePaths(frame, step: 2, excludeNodes: [db])
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [(nodeIndex: db, to: pick, duration: flight)],
                zoneMoves(c, plan: frame.plan, p: 1, exclude: [db], d: flight)
            ).filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: air(pick.x, pick.z), apex: 4.5, duration: flight),
            duration: flight,
            reaches: [db, receiver]
        ))

        // Return: DB takes it back the other way ~5yd while the offense
        // scrambles after him; pulse the DB.
        let returnSpot = player(pick.x, pick.z - c.direction * 5)
        steps.append(Step(
            moves: merge(
                [(nodeIndex: db, to: returnSpot, duration: 1.0)],
                trailMoves(c, toX: returnSpot.x, toZ: returnSpot.z,
                           roles: Array(Set([0, receiverRole, 9])), fraction: 0.5, d: 1.0)
            ),
            ballMove: .carry(nodeIndex: db),
            duration: 1.0,
            pulses: [db]
        ))
        steps.append(Step(moves: [], ballMove: .carry(nodeIndex: db), duration: 0.5))
        return steps
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
        let hang: TimeInterval = 2.1  // punt hang time (visual compromise)
        var coverage: [Move] = []
        for role in 1...10 {
            let start = c.offense[role]
            let depth: Float = (role == 7 || role == 8) ? 2 : 6
            coverage.append((c.oBase + role,
                             player(start.x * 0.85, clampZ(landZ - c.direction * depth)), hang))
        }
        // Return unit falls back to wall off in front of the returner.
        var wall: [Move] = []
        for role in 0..<11 where c.dBase + role != returner {
            let start = c.defense[role]
            wall.append((c.dBase + role,
                         player(lerp(start.x, Float(role % 3 - 1) * 4, 0.5),
                                lerp(start.z, clampZ(landZ - c.direction * 7), 0.7)), hang))
        }

        let returnEnd = player(1, landZ - c.direction * 3)
        return [
            // Long snap slides back to the punter.
            Step(
                moves: [],
                ballMove: .slide(to: ground(punterSpot.x, punterSpot.z), duration: 0.5),
                duration: 0.6,
                sound: .snap
            ),
            // Boot: high arc downfield; coverage races under it while the
            // return unit sets its wall and the returner settles.
            Step(
                moves: merge([(nodeIndex: returner, to: player(0, landZ), duration: hang)],
                             coverage + wall),
                ballMove: .arc(to: air(0, landZ), apex: 12, duration: hang),
                duration: hang,
                sound: .kickThump
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
                duration: 0.5,
                sound: .snap
            ),
            // Hold beat.
            Step(moves: [], ballMove: nil, duration: 0.35),
            // The kick: both lines surge into the pile as it goes up.
            Step(
                moves: lineSurgeMoves(c, p: 0.8, d: 0.5),
                ballMove: .arc(to: SCNVector3(clampX(targetX), targetY, postZ), apex: 8, duration: 1.6),
                duration: 1.7,
                sound: .kickThump
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
        let hang: TimeInterval = 2.4  // real kickoff hang time
        var bootMoves: [Move] = [(returner, player(0, catchZ), hang)]
        for i in 1...10 {
            bootMoves.append((kBase + i, player(kicking[i].x * 0.8, clampZ(ownYard(22))), hang))
        }
        bootMoves.append((kBase, player(0, teeZ + kickDir * 4), hang))
        for i in 0..<5 {
            bootMoves.append((rBase + i, player(receiving[i].x * 0.55, clampZ(ownYard(18))), hang))
        }
        for i in 5..<9 {
            bootMoves.append((rBase + i, player(receiving[i].x * 0.7, clampZ(ownYard(10))), hang))
        }
        bootMoves.append((rBase + 9, player(-2, clampZ(ownYard(6))), hang))
        steps.append(Step(
            moves: bootMoves,
            ballMove: .arc(to: air(0, catchZ), apex: 16, duration: hang),
            duration: hang,
            reaches: [returner],
            sound: .kickThump
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
        // Return covered at a returner's sprint (~9 yd/s), not warp speed.
        let runDuration = TimeInterval(min(max(runDistance / 9.0, 1.2), 3.6))
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
                 ballMove: c.snapExchange, duration: 0.45,
                 startDelays: snapReactionDelays(c)),
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
                 ballMove: c.snapExchange, duration: 0.6,
                 blocks: lineBlockNodes(c),
                 startDelays: snapReactionDelays(c)),
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
