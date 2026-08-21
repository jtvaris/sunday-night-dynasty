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
                          offenseNumbers: [Int]? = nil, defenseNumbers: [Int]? = nil,
                          mirror: Float = 1)
        -> (home: [(x: Float, z: Float, number: Int)], away: [(x: Float, z: Float, number: Int)]) {
        var offense = offensePositions(for: playType, call: call, losZ: losZ,
                                       direction: direction, mirror: mirror)
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
    /// OL/DL/TE dig into a deep 3-point with the hand down, the RB sits in a
    /// back-specific crouch while LB/S share the generic 2-point, WR/CB stand
    /// in an upright split stance. The QB waits in a dedicated shotgun pose,
    /// but bends over the C with his hands out when the CALL puts him under
    /// center — the snap exchange starts from that pose.
    static func stances(offenseIsHome: Bool, call: OffensivePlayCall? = nil)
        -> (home: [Int: FootballFieldScene.Stance], away: [Int: FootballFieldScene.Stance]) {
        var offense: [Int: FootballFieldScene.Stance] = [1: .runningBack, 10: .threePoint]
        // Same family grouping the alignment uses: an I-form or play-action
        // snap starts hand-to-hand under center, everything else from the gun.
        switch call?.formationFamily {
        case .iForm, .playAction:
            offense[0] = .underCenter
        case .special:
            offense[0] = call == .kneel ? .underCenter : .shotgunQB
        default:
            offense[0] = .shotgunQB
        }
        for role in 2...6 { offense[role] = .threePoint }   // OL
        for role in [7, 8, 9] { offense[role] = .split }    // WRs
        var defense: [Int: FootballFieldScene.Stance] = [:]
        for role in 0...3 { defense[role] = .threePoint }   // DL
        for role in [4, 5, 6, 9, 10] { defense[role] = .linebacker }  // LBs + safeties: ready coil
        for role in [7, 8] { defense[role] = .cornerback }  // CBs: pressed low coil
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
                            offenseNumbers: [Int]? = nil, defenseNumbers: [Int]? = nil,
                            mirror: Float = 1)
        -> (home: [(x: Float, z: Float, number: Int)], away: [(x: Float, z: Float, number: Int)]) {
        formation(
            for: play.playType,
            call: call,
            defensivePackage: defensivePackage,
            losZ: losZ(yardLine: losYardLine, offenseIsHome: offenseIsHome),
            direction: offenseIsHome ? 1 : -1,
            offenseNumbers: offenseNumbers,
            defenseNumbers: defenseNumbers,
            mirror: mirror
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
                                 losZ: Float, direction: Float, mirror: Float = 1)
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
            // The call's FORMATION FAMILY drives the alignment — the same
            // grouping `OffensivePlayCall.formationFamily` uses for audibles,
            // so every call in a family snaps from the look its family names
            // (and a new play can never silently fall into the base gun).
            switch call?.formationFamily {
            case .iForm:
                // I-formation: QB under center, back deep downhill, tight splits.
                qbDepth = 1.2; rb = (0, 5.5); wrSplit = 12; slot = (-7, 1.2); teX = 4.2
            case .stretch:
                qbDepth = 4.5; rb = (-2.5, 5.2); wrSplit = 14; slot = (-8, 1.3)
            case .backfield:
                qbDepth = 5.5; rb = (1.8, 5.5)
            case .quick:
                qbDepth = 4; wrSplit = 15; slot = (-9, 1.3)
            case .crossSet:
                // Slot flips to the right so the two crossers X the field.
                qbDepth = 5; wrSplit = 16; slot = (8, 1.5)
            case .spreadDeep:
                // Spread: maximum width, everyone in the pattern.
                qbDepth = 5.5; wrSplit = 17; slot = (-11, 1.4)
            case .pistol:
                // Read/RPO set: QB four deep, the back stacked behind him so
                // the mesh can go either way.
                qbDepth = 4; rb = (0, 6.8); wrSplit = 15; slot = (-9, 1.4)
            case .playAction:
                // Under center with the back on a downhill track — the fake
                // only sells from the look the run comes out of.
                qbDepth = 1.3; rb = (0, 5.2); wrSplit = 15; slot = (-9, 1.3); teX = 4.5
            case .baseGun, .special, .none:
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
        // `mirror` (±1) is the coach's REVERSE flip: reflect the final X across
        // the ball so rb/slot/teX flip and WR-L/R swap; QB/OL (x=0) are fixed
        // points. `mirror == 1` is byte-for-byte the old alignment.
        return raw.map { (x: clampX($0.x * mirror), z: clampZ($0.z), number: $0.number) }
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
        let cbSplit: Float = 15
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
        case .odd34:
            // Two-gap odd front: nose over the ball, ends head-up on the
            // tackles, and the backers stand free behind it.
            dlXs = [-4.2, -0.9, 0.9, 4.2]
            dlDepth = 1.1
            lbSpots = [(-4, 4.2), (0, 4.6), (4, 4.2)]
        case .bigNickel:
            // Third safety walks down over the tight end instead of a backer.
            lbSpots = [(-3.5, 4.5), (1.5, 4.8), (7.5, 4.0)]
            sSpots = [(-6, 12), (6, 12)]
        default:
            break
        }

        switch package?.coverage {
        case .manToMan:
            // Press: corners up in the receivers' faces.
            cbDepth = min(cbDepth, 1.6)
            if package?.front != .goalLine { sSpots = [(-6, 10), (6, 10)] }
        case .cover0:
            // Zero help: press everywhere and both safeties in the box.
            cbDepth = min(cbDepth, 1.4)
            sSpots = [(-5, 5), (5, 5)]
        case .tampa2:
            // Two-high with squatting corners — the Mike runs the pipe.
            cbDepth = min(cbDepth, 5)
            sSpots = [(-10, 14), (10, 14)]
            lbSpots[1] = (0, 5.5)
        case .cover6:
            // Split field: quarters to the field, cover 2 to the boundary.
            cbDepth = max(cbDepth, 7)
            sSpots = [(-8, 14), (5, 11)]
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
        case .fireZone:
            // The two men who are coming show it: the field backer walks up
            // outside the end and the Mike creeps into the A gap behind him
            // (the backside end is the one bailing out).
            lbSpots[2] = (6.5, 2.2)
            lbSpots[1] = (0.5, 3.0)
        case .simPressure:
            // Creeper: everybody SHOWS heat pre-snap — the rush still counts
            // four, because an end is bailing out behind the late backer.
            lbSpots = lbSpots.map { (x: $0.x * 0.8, depth: min($0.depth, 3.0)) }
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
                      defenseSpeeds: [Float]? = nil,
                      mirror: Float = 1)
        -> [FootballFieldScene.PlayStep] {
        let context = Context(play: play, losYardLine: losYardLine, offenseIsHome: offenseIsHome,
                              matchups: matchups, call: call, defensivePackage: defensivePackage,
                              offenseSpeeds: offenseSpeeds, defenseSpeeds: defenseSpeeds,
                              mirror: mirror)
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
        /// How the call is EXECUTED: blocking scheme, drop rhythm, what the QB
        /// does with the ball. Data, read straight off the call — the scripts
        /// branch on this, never on a play by name.
        let shape: RouteSpec.Shape
        /// Role-ordered top speeds (yd/s) fed from the real units' speed
        /// attributes; defaults when the caller supplies none.
        let offenseSpeeds: [Float]
        let defenseSpeeds: [Float]
        /// The coach's REVERSE flip (±1), offense-relative — already baked into
        /// `offense` here; forwarded to `spec.points` so the routes reflect too.
        let mirror: Float

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
             defenseSpeeds: [Float]? = nil,
             mirror: Float = 1) {
            self.play = play
            self.mirror = mirror
            self.losZ = PlayChoreographer.losZ(yardLine: losYardLine, offenseIsHome: offenseIsHome)
            self.direction = offenseIsHome ? 1 : -1
            self.oBase = offenseIsHome ? 0 : 11
            self.dBase = offenseIsHome ? 11 : 0
            self.offense = PlayChoreographer.offensePositions(for: play.playType, call: call,
                                                              losZ: losZ, direction: direction,
                                                              mirror: mirror)
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
            self.shape = RouteSpec.shape(for: call)
        }

        /// Blown assignment the SIM decided, when it named one on the field.
        var bust: (kind: PlayBustKind, offRole: Int?, defRole: Int?)? {
            guard let matchups, let kind = matchups.bustKind else { return nil }
            return (kind, matchups.bustOffRole, matchups.bustDefRole)
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

    /// The front's marching orders for one run: which way the whole line
    /// works, where the ball is aiming, and who pulls. Every field is derived
    /// from the carrier's OWN spec track (already mirror-baked), so a Wide
    /// Zone and a Duo can never move the trenches the same way — and no play
    /// needs a bespoke entry anywhere.
    private struct RunBlocking {
        var scheme: RouteSpec.RunScheme = .manDown
        /// Lateral flow in FIELD space, -1…1 (+ = toward +x).
        var flow: Float = 0
        /// Field x the ball is aiming at.
        var aimX: Float = 0
        /// OL role wrapping to the point of attack (gap schemes only).
        var puller: Int?
        /// The blocker the SIM says blew his assignment — he whiffs and his
        /// man comes through clean.
        var bustedBlocker: Int?
    }

    /// Run blocking: the OL works the concept and the DL meets it at the LOS.
    /// `dlShift` > 0 pushes the DL backward off the ball (the line is winning);
    /// < 0 lets it penetrate into the backfield (the front got beat).
    /// Zone flows laterally as one body, gap down-blocks and wraps the puller,
    /// man/down blocking fires straight ahead, a sneak surge is one pile.
    private static func lineSurgeMoves(_ c: Context, p: Float, d: TimeInterval,
                                       dlShift: Float = 0,
                                       blocking: RunBlocking? = nil) -> [Move] {
        var moves: [Move] = []
        let plan = blocking ?? RunBlocking()
        let flow = plan.flow
        let surgeDepth = c.losZ + c.direction * (0.25 + max(0, dlShift) * 0.6)
        for i in 0..<5 {
            let role = 2 + i
            let start = c.offense[role]
            if role == plan.puller {
                // The puller clears his own hip, runs flat BEHIND the line, and
                // turns up into the hole — the shape that makes a gap scheme
                // read as a gap scheme.
                let target = clampX(plan.aimX + flow * 1.8)
                let depth = lerp(start.z, c.losZ + c.direction * 0.8, p)
                    - c.direction * 0.9 * sin(Float.pi * min(max(p, 0), 1))
                moves.append((c.oBase + role, player(lerp(start.x, target, p), depth), d))
                continue
            }
            var x = start.x + jitters[i] * p
            var z = lerp(start.z, surgeDepth, p)
            switch plan.scheme {
            case .zone:
                // Everybody reaches playside in step — the whole front slides.
                x += flow * 1.9 * p
                z = lerp(start.z, c.losZ + c.direction * (0.1 + max(0, dlShift) * 0.5), p)
            case .gap:
                // Down blocks work BACK against the flow to seal the crease.
                x -= flow * 0.9 * p
            case .surge:
                // One body, straight ahead, shoulders square.
                x = start.x + jitters[i] * 0.3 * p
                z = lerp(start.z, c.losZ + c.direction * (0.9 + max(0, dlShift) * 0.6), p)
            case .manDown, .none:
                break
            }
            // A blown assignment: he lunges at air while his man runs by.
            if role == plan.bustedBlocker { x = start.x - flow * 0.6 * p }
            moves.append((c.oBase + role, player(x, z), d))
        }
        // The DL fights the same flow — except the man whose blocker whiffed,
        // who arrives in the backfield untouched.
        let freeRusher = plan.bustedBlocker.flatMap { facingRusher($0) }
        for i in 0..<4 {
            let start = c.defense[i]
            if i == freeRusher {
                moves.append((c.dl(i),
                              player(lerp(start.x, plan.aimX, p * 0.7),
                                     lerp(start.z, c.losZ - c.direction * 1.6, p)), d))
                continue
            }
            let flowShift = plan.scheme == .zone ? flow * 0.9 * p : 0
            moves.append((c.dl(i),
                          player(start.x - jitters[i] * 0.5 * p + flowShift,
                                 lerp(start.z, c.losZ + c.direction * (0.7 + dlShift), p)), d))
        }
        return moves
    }

    /// The DL role squared up on an OL role — the inverse of `blockerFacing`.
    private static func facingRusher(_ olRole: Int) -> Int? {
        switch olRole {
        case 2: return 0; case 3: return 1
        case 5: return 2; case 6: return 3; default: return nil
        }
    }

    /// The front's orders for THIS run, read off the design: the carrier's
    /// spec track gives the flow and the aiming point, the call's shape gives
    /// the scheme and whether a guard pulls, and the sim gives the bust.
    private static func runBlocking(_ c: Context, shape: RoutePath,
                                    carrierStart: (x: Float, z: Float)) -> RunBlocking {
        var plan = RunBlocking()
        plan.scheme = c.shape.run == .none ? .manDown : c.shape.run
        // Where the track is headed once he clears the mesh (field space).
        let aim = shape.point(at: 0.6)
        plan.aimX = clampX(aim.x)
        plan.flow = min(max((aim.x - carrierStart.x) / 3.5, -1), 1)
        if c.shape.pulls {
            // The BACKSIDE guard wraps: the one aligned away from the flow.
            let guards = [3, 5].sorted { c.offense[$0].x < c.offense[$1].x }
            plan.puller = plan.flow >= 0 ? guards[0] : guards[1]
        }
        if let bust = c.bust, bust.kind == .block, let role = bust.offRole,
           (2...6).contains(role), role != plan.puller {
            plan.bustedBlocker = role
        }
        return plan
    }

    /// Pass protection: the OL sets a pocket (tackles deeper than the
    /// interior) and each rusher works to HIS blocker's set point — the
    /// OL/DL pairs lock up chest to chest (the step's `blocks` list adds the
    /// punch-and-shove pose on top). When `beatenBlocker` names an OL role
    /// (2-6), THAT side caves visibly deeper and his man drives THROUGH the
    /// spot (the sack collapse side).
    /// `dropping` names DL roles bailing into coverage (fire zone / creeper):
    /// they are left out of the rush entirely so the zone machinery owns them.
    private static func pocketMoves(_ c: Context, p: Float, d: TimeInterval,
                                    beatenBlocker: Int? = nil,
                                    dropping: Set<Int> = []) -> [Move] {
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
        for i in 0..<4 where !dropping.contains(i) {
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
    /// A lineman dropping into coverage is not in a block engagement.
    private static func lineBlockNodes(_ c: Context, dropping: Set<Int> = []) -> [Int] {
        (2...6).map { c.oBase + $0 }
            + (0...3).filter { !dropping.contains($0) }.map { c.dl($0) }
    }

    /// Per-node block STYLE from the trench matchup so the winning side of
    /// each rep visibly wins it: run blocks drive, pass sets anchor, a decided
    /// rep pancakes the loser, a beaten protector gets swum past. Deterministic
    /// (seeded by node/spot) — pure presentation, the block list is unchanged.
    private static func blockStyleMap(_ c: Context, run: Bool,
                                      beatenBlocker: Int? = nil)
        -> [Int: FootballFieldScene.BlockStyle] {
        var m: [Int: FootballFieldScene.BlockStyle] = [:]
        for role in 2...6 { m[c.oBase + role] = run ? .drive : .anchor }
        for role in 0...3 { m[c.dl(role)] = run ? .anchor : .drive }

        // The DL squared up on an OL role (inverse of blockerFacing).
        func facingDL(_ olRole: Int) -> Int? {
            switch olRole {
            case 2: return 0; case 3: return 1
            case 5: return 2; case 6: return 3; default: return nil
            }
        }

        // The sim's trench/pressure verdicts: the winner pancakes his man.
        for event in c.matchups?.events ?? [] where event.kind == .trench || event.kind == .pressure {
            if event.offenseWon, let ol = event.offRole, (2...6).contains(ol) {
                m[c.oBase + ol] = .pancake
                if let dl = facingDL(ol) { m[c.dl(dl)] = .anchor }
            } else if !event.offenseWon, let dl = event.defRole, (0...3).contains(dl) {
                m[c.dl(dl)] = .pancake
                m[c.oBase + blockerFacing(defRole: dl)] = .whiff
            }
        }

        // The beaten pass-pro side: the OL whiffs, his rusher drives through.
        if let beaten = beatenBlocker, (2...6).contains(beaten) {
            m[c.oBase + beaten] = .whiff
            if let dl = facingDL(beaten) { m[c.dl(dl)] = .drive }
        }

        // One interior lineman cuts on a wide-open run lane — deterministic
        // per spot so the trenches never move in perfect lockstep.
        let cutRole = 2 + Int(hash01(c.oBase &* 17 &+ Int(c.losZ)) * 4.99) % 5
        let cut = c.oBase + cutRole
        if run && c.holeSize > 0.55 && m[cut] == .drive { m[cut] = .cut }
        return m
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
             to: player(x + (offset == 0 ? 0.5 : -0.5), z - c.direction * 0.25),
             duration: 0.28)   // snap onto the pile fast so each man falls AS he arrives
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
                                      depthScale: depthScale, mirror: c.mirror) else { return nil }
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
                                    depthScale: depthScale, mirror: c.mirror)
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
        /// DL roles (0-3) that BAIL OUT into coverage instead of rushing —
        /// the dropping end that makes a fire zone a fire zone. They must be
        /// skipped by the pocket/block machinery or they'd be in two places.
        var droppers: Set<Int> = []
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
        case .fireZone:
            // FIVE come and the backside END bails into the hook behind them:
            // both the Mike and the field backer are in the rush (3 remaining
            // linemen + 2 backers = 5), which is exactly what separates a fire
            // zone from the creeper below — that one still rushes four.
            plan.blitzers = [5, 6]
            plan.droppers = [0]
        case .simPressure:
            // The creeper: the backer who showed heat drops back out and the
            // strongside end replaces him in the rush lane. Still four rushers.
            plan.blitzers = [4]
            plan.droppers = [3]
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
        case .cover0:
            // Every eligible is locked man-to-man and NOBODY is home behind it.
            plan.man = [7: 7, 8: 8, 9: 9, 5: 10, 6: 1]
            plan.zones = [4: (-3, 4), 10: (4, 4)]
        case .tampa2:
            // Two deep halves, corners squat the flats, and the Mike sprints
            // the pipe to the deep middle hole.
            plan.zones = [7: (-13, 5), 8: (13, 5), 9: (-10, 15), 10: (10, 15),
                          4: (-8, 7), 5: (0, 17), 6: (8, 7)]
        case .cover6:
            // Split field: quarters to the left, cover 2 to the right.
            plan.zones = [7: (-13, 13), 8: (13, 5), 9: (-6, 14), 10: (8, 15),
                          4: (-8, 6), 5: (0, 8), 6: (7, 6)]
        default:
            // Cover 3 shell for the base call and undialed defenses.
            plan.zones = [7: (-12, 15), 8: (12, 15), 9: (0, 16), 10: (9, 6),
                          4: (-8, 5.5), 5: (0, 6.5), 6: (4.5, 5.5)]
        }
        for role in plan.blitzers {
            plan.man.removeValue(forKey: role)
            plan.zones.removeValue(forKey: role)
        }
        // A dropping lineman falls into the shallow hook on his own side — the
        // zone machinery then carries him like any other underneath defender.
        for role in plan.droppers {
            let start = c.defenseStart(role)
            plan.zones[role] = (start.x * 0.8, 5.5)
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
    /// the QB. Double A-Gap sends both backers inside the center;
    /// safety/corner pressure bends around the edge.
    ///
    /// `launch` is where the QB ACTUALLY ends up when the call rolls him out
    /// (the end of the track he runs). A blitzer has eyes on the ball: on a
    /// boot he chases the passer to the edge instead of arriving, unblocked
    /// and alone, at the spot the QB vacated at the snap. Nil = a straight
    /// dropback, where the pocket IS the destination (unchanged).
    private static func blitzPath(role: Int, c: Context, qbDropZ: Float,
                                  launch: (x: Float, z: Float)? = nil) -> RoutePath {
        let start = c.defenseStart(role)
        let gapX: Float
        if c.package?.blitz == .doubleAGap && (role == 4 || role == 5) {
            gapX = role == 4 ? -1.0 : 1.0
        } else if role >= 9 {
            gapX = start.x < 0 ? -5.5 : 5.5
        } else {
            gapX = start.x * 0.5
        }
        // Terminal point: a stride in FRONT of wherever the passer is throwing
        // from — his rolled-out launch spot when the design moved him, else the
        // drop depth over his alignment.
        let end: (x: Float, z: Float) = launch.map { ($0.x, $0.z) }
            ?? (gapX * 0.3, qbDropZ)
        return RoutePath(points: [
            (start.x, start.z),
            (clampX(gapX), clampZ(c.losZ - c.direction * 0.3)),
            (clampX(end.x), clampZ(end.z + c.direction * 1.2)),
        ])
    }

    /// Everything shared by the dropback scripts, precomputed per play:
    /// step durations, every route runner's per-step path slices, man
    /// mirrors, zone drops and blitz lanes. Frame steps: 0 snap, 1 drop,
    /// 2 throw/flight.
    private struct DropbackFrame {
        var durations: [TimeInterval]
        var qbDrop: SCNVector3
        /// The QB's designed rollout track, when the call draws him one — the
        /// dropback step runs him through it instead of backpedalling.
        var qbPath: RoutePath?
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
                                      qbDropZ: Float,
                                      qbDropX: Float? = nil,
                                      qbPath: RoutePath? = nil) -> DropbackFrame {
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
        // BUST — the sim said this man doesn't know the play yet. He breaks
        // the route off at the wrong depth and rounds the cut off; the ball
        // still goes where the DESIGN said it would, so the coach sees the
        // miss for exactly what it was. No dice rolled here.
        //
        // ONLY on an incompletion. Truncating a route the sim CAUGHT would
        // desync the catch spot from the ball's flight (the ball is aimed at a
        // point on the full route, the receiver would stop 45% short of it and
        // the pass would land on nobody). The sim only ever stamps a route bust
        // on its incompletion path today — this guard is what keeps that a
        // property of the choreography rather than an accident of the sim.
        if c.play.outcome == .incompletion,
           let bust = c.bust, bust.kind == .route, let role = bust.offRole,
           let full = routes[role] {
            routes[role] = full.prefix(to: 0.55)
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

        // BUST — a coverage defender who doesn't know the call. He is pulled
        // out of his man/zone assignment entirely: a beat frozen at the snap,
        // then a drop to the WRONG landmark (the hook he thought he had),
        // leaving his man running free. The sim already gave up the catch.
        if let bust = c.bust, bust.kind == .coverage, let role = bust.defRole,
           !plan.blitzers.contains(role), !plan.droppers.contains(role) {
            plan.man.removeValue(forKey: role)
            let start = c.defenseStart(role)
            plan.zones[role] = (start.x * 0.35, 6.5)
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
        // On a designed rollout the pressure chases the QB's REAL launch spot
        // (the end of the track he runs), not the pocket he left behind.
        let launchSpot: (x: Float, z: Float)? = qbPath.map { ($0.end.x, $0.end.z) }
        for role in plan.blitzers {
            let lane = blitzPath(role: role, c: c, qbDropZ: qbDropZ, launch: launchSpot)
            defenseSlices[role] = pathMoves(lane, nodeIndex: c.dBase + role,
                                            fractions: rushFractions, durations: durations)
        }

        return DropbackFrame(durations: durations,
                             qbDrop: player(qbDropX ?? c.offenseStart(0).x, qbDropZ),
                             qbPath: qbPath,
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

    /// A defender's field position at the START of the flight step (after the
    /// drop): the end of his most recent route/blitz slice, else his zone
    /// landmark, else his pre-snap spot. Used to keep late-arriving men moving
    /// FROM where they actually are (never a teleport back to alignment).
    private static func defenseCurrent(_ role: Int, frame: DropbackFrame,
                                       c: Context) -> (x: Float, z: Float) {
        if let slices = frame.defenseSlices[role] {
            let upto = min(1, slices.count - 1)
            for step in stride(from: upto, through: 0, by: -1) {
                if let move = slices[step], let last = move.points.last {
                    return (last.x, last.z)
                }
            }
        }
        if let landmark = frame.plan.zones[role] {
            return (landmark.x, c.losZ + c.direction * landmark.depth)
        }
        return (c.defense[role].x, c.defense[role].z)
    }

    /// Keeps EVERY node moving through the ball's flight so nobody freezes when
    /// the throw leaves the QB's hand. `covered` is every node the step's
    /// route/coverage/zone paths already animate; this fills in the rest with
    /// role-appropriate continuation: the trenches keep grinding (OL hold their
    /// sets, the front four presses), receivers whose routes are done turn
    /// upfield toward the ball, and any coverage defender whose assignment
    /// finished (a run-off man mirror, a blitzer arriving late) breaks toward
    /// the ball — capped so nobody flies across the field. The QB is left to
    /// his `throwMotion` follow-through (a positional move would read as jogging
    /// mid-throw). Pure presentation: positions only, the sim is untouched.
    private static func flightSupportMoves(_ c: Context, frame: DropbackFrame,
                                           ballSpot: (x: Float, z: Float),
                                           covered: Set<Int>, d: TimeInterval) -> [Move] {
        var moves: [Move] = []
        // Trenches keep battling: OL hold their pass sets, the DL keeps pressing
        // (the `blocks` list on the step adds the punch-and-shove pose on top).
        for move in pocketMoves(c, p: 1, d: d, dropping: frame.plan.droppers)
        where !covered.contains(move.nodeIndex) {
            moves.append(move)
        }
        // Eligibles whose route already finished turn upfield and work back
        // toward the ball instead of standing at their route end.
        for role in [1, 7, 8, 9, 10] {
            let idx = c.oBase + role
            guard !covered.contains(idx), let from = frame.routeEnds[role] else { continue }
            moves.append((idx,
                          player(clampX(lerp(from.x, ballSpot.x, 0.2)),
                                 clampZ(from.z + c.direction * 2)), d))
        }
        // Coverage men whose assignment is done break on the ball from where
        // they actually are — a controlled close, capped at 5 yd.
        for role in 4..<11 {
            let idx = c.dBase + role
            guard !covered.contains(idx) else { continue }
            let from = defenseCurrent(role, frame: frame, c: c)
            var tx = lerp(from.x, ballSpot.x, 0.3)
            var tz = lerp(from.z, ballSpot.z, 0.3)
            let dx = tx - from.x, dz = tz - from.z
            let dist = (dx * dx + dz * dz).squareRoot()
            if dist > 5 { tx = from.x + dx / dist * 5; tz = from.z + dz / dist * 5 }
            moves.append((idx, player(clampX(tx), clampZ(tz)), d))
        }
        return moves
    }

    /// The block lists for a flight step: both lines grind on, and a back who
    /// stayed in to protect churns in his pass set too.
    private static func flightBlocks(_ c: Context, frame: DropbackFrame)
        -> (nodes: [Int], styles: [Int: FootballFieldScene.BlockStyle]) {
        var nodes = lineBlockNodes(c, dropping: frame.plan.droppers)
        var styles = blockStyleMap(c, run: false)
        if frame.rbBlocks {
            nodes.append(c.rb)
            styles[c.rb] = .anchor
        }
        return (nodes, styles)
    }

    /// What the QB sells before he throws.
    private enum SnapFake {
        /// Straight dropback — he takes it and goes.
        case none
        /// Play action: he rides the fake to the back and turns his back to
        /// the defense; the box bites downhill (when the sim says it did).
        case playAction
        /// RPO: a real ride at the mesh with his eyes on the read defender,
        /// then the ball comes out NOW.
        case rpoRide
    }

    /// Frame step 0: the snap — pocket sets, all routes release, zones sink,
    /// blitzers show. A fake first sells the run: the QB rides it, the back
    /// plunges into the line empty, and the linebackers bite downhill before
    /// recovering.
    private static func snapStep(_ c: Context, frame: DropbackFrame, fake: SnapFake) -> Step {
        let d = frame.durations[0]
        let isPA = fake != .none
        var scripted: [Move] = []
        if fake == .rpoRide {
            // The ride happens AT the mesh: he opens to the back, ball extended,
            // eyes on the read key — then pulls it. The mesh point is derived
            // from the two already-mirrored alignments, so REVERSE flows through.
            let qbStart = c.offenseStart(0)
            let rbStart = c.offenseStart(1)
            let dx = rbStart.x - qbStart.x, dz = rbStart.z - qbStart.z
            let len = max((dx * dx + dz * dz).squareRoot(), 0.001)
            scripted.append((c.qb,
                             player(qbStart.x + dx / len * 0.8, qbStart.z + dz / len * 0.8),
                             d * 0.85))
        } else if fake == .playAction {
            // The ride opens toward the run's side, so both lateral constants
            // are reflected by the coach's REVERSE flip — otherwise a mirrored
            // boot fakes one way and the play goes the other. (The alignments
            // themselves arrive already mirrored; these are DISPLACEMENTS off
            // them, so they need the flip applied here.)
            let qbStart = c.offenseStart(0)
            scripted.append((c.qb,
                             player(qbStart.x + 0.6 * c.mirror, qbStart.z + c.direction * 0.8),
                             d * 0.9))
            if frame.rbBlocks {
                scripted.append((c.rb, player(0.4 * c.mirror, c.losZ + c.direction * 0.3), d))
            }
        } else if frame.rbBlocks {
            // The back scans for work at the pocket's front porch.
            let rbStart = c.offenseStart(1)
            scripted.append((c.rb, player(rbStart.x * 0.7, c.losZ - c.direction * 3.4), d))
        }
        var zone = zoneMoves(c, plan: frame.plan, p: 0.45, d: d)
        // R37: the linebackers step downhill ONLY when the sim says they bit
        // on the fake (`defenseBitOnFake`). A veteran box that read it plays
        // its zones like any other dropback; nil (older data) keeps the old
        // always-bite look.
        if isPA, c.play.defenseBitOnFake ?? true {
            zone = zone.map { move in
                let role = move.nodeIndex - c.dBase
                guard [4, 5, 6].contains(role) else { return move }
                let start = c.defense[role]
                return (move.nodeIndex, player(start.x * 0.7, c.losZ + c.direction * 2), d)
            }
        }
        let paths = framePaths(frame, step: 0)
        let taken = Set(paths.map(\.nodeIndex))
        let moves = merge(scripted,
                          pocketMoves(c, p: 0.45, d: d, dropping: frame.plan.droppers) + zone)
            .filter { !taken.contains($0.nodeIndex) }
        return Step(moves: moves, paths: paths, ballMove: c.snapExchange, duration: d,
                    blocks: lineBlockNodes(c, dropping: frame.plan.droppers),
                    blockStyles: blockStyleMap(c, run: false),
                    startDelays: bustDelays(c, base: snapReactionDelays(c)))
    }

    /// Snap reactions with the busted man's hesitation folded in: a player who
    /// doesn't know the call stands there a beat looking for his key while the
    /// other ten fire off. His own next move takes over from there, so the
    /// delay costs him ground without stranding him.
    private static func bustDelays(_ c: Context, base: [Int: TimeInterval]) -> [Int: TimeInterval] {
        guard let bust = c.bust else { return base }
        var out = base
        if let role = bust.offRole { out[c.oBase + role] = 0.55 }
        if let role = bust.defRole { out[c.dBase + role] = 0.5 }
        return out
    }

    /// Frame step 1: the dropback — the QB backpedals to depth (eyes down
    /// the field, ball in both hands at the chest), routes stem, zones keep
    /// sinking, the rush pushes the pocket. `pumpFake` sells a deep-shot
    /// pump at the top of the drop (~30% of deep throws).
    private static func dropStep(_ c: Context, frame: DropbackFrame,
                                 pumpFake: Bool = false) -> Step {
        let d = frame.durations[1]
        var paths = framePaths(frame, step: 1)
        // A designed rollout is a RUN, not a backpedal: he sprints his track
        // (turning his shoulders to the flow) and throws off the move.
        var qbScripted: [Move] = []
        var backpedals: [Int] = []
        if let qbPath = frame.qbPath {
            paths.append((c.qb, qbPath.slice(from: 0, to: 1).map { player($0.x, $0.z) }, d))
        } else {
            qbScripted.append((nodeIndex: c.qb, to: frame.qbDrop, duration: d))
            backpedals.append(c.qb)
        }
        let taken = Set(paths.map(\.nodeIndex))
        let moves = merge(qbScripted,
                          pocketMoves(c, p: 1, d: d, dropping: frame.plan.droppers)
                              + zoneMoves(c, plan: frame.plan, p: 0.9, d: d))
            .filter { !taken.contains($0.nodeIndex) }
        return Step(moves: moves, paths: paths, ballMove: .carryChest(nodeIndex: c.qb),
                    duration: d, backpedals: backpedals,
                    blocks: lineBlockNodes(c, dropping: frame.plan.droppers),
                    pumpFakes: pumpFake ? [c.qb] : [],
                    // Mobile QBs sell the quick shoulder shrug; pocket passers
                    // the full double-clutch wind-up.
                    pumpFakeQuick: c.oSpeed(0) >= 8.2,
                    blockStyles: blockStyleMap(c, run: false))
    }

    /// QB drop depth past his alignment for a drop of `steps` steps. From
    /// under center he covers the real ground (3-step ≈ 3.2 yd, 5-step ≈ 4.8,
    /// 7-step ≈ 6.5); from the gun the same rhythm is a settle of a yard or
    /// two, because he starts five yards deep already.
    ///
    /// The step ladder is for CALLED plays, whose drop rhythm the concept
    /// actually specifies. A snap with no call has no rhythm to honor — the
    /// AI just drove — so it keeps the two-tier depths it has always used
    /// (deep 4.8/2.5, everything else 3.2/1.5), byte-for-byte.
    private static func dropDepth(_ c: Context, steps: Int) -> Float {
        guard c.call != nil else {
            return steps >= 7 ? (c.qbUnderCenter ? 4.8 : 2.5)
                              : (c.qbUnderCenter ? 3.2 : 1.5)
        }
        switch steps {
        case 0:  return c.qbUnderCenter ? 1.5 : 0.6   // ball out on rhythm
        case 3:  return c.qbUnderCenter ? 3.2 : 1.5
        case 7:  return c.qbUnderCenter ? 6.5 : 3.0
        default: return c.qbUnderCenter ? 4.8 : 2.2
        }
    }

    /// The drop rhythm this snap calls for: the CALL's own (quick game three,
    /// deep shot seven, RPO/screen none), deepened when the sim's throw is
    /// far deeper than the design asked for. No call → depth decides.
    private static func dropSteps(_ c: Context, airDepth: Float) -> Int {
        guard c.call != nil else { return airDepth >= 15 ? 7 : 5 }
        let called = c.shape.dropSteps
        return airDepth >= 18 ? max(called, 7) : called
    }

    /// How long the snap beat lasts: a straight snap is quick, a full play
    /// fake takes a beat to sell, an RPO ride is real but hurried — the ball
    /// has to be out before the read defender can be right.
    private static func snapBeat(_ fake: SnapFake) -> TimeInterval {
        switch fake {
        case .none:       return 0.65
        case .playAction: return 1.0
        case .rpoRide:    return 0.8
        }
    }

    /// How long that drop takes (the dropback step's duration).
    private static func dropDuration(_ steps: Int) -> TimeInterval {
        switch steps {
        case 0:  return 0.5
        case 3:  return 0.95
        case 7:  return 1.6
        default: return 1.25
        }
    }

    /// The dropback step's duration for THIS launch point. A designed boot or
    /// sprint-out makes the QB cover real ground in that same beat, so the
    /// window is stretched to at least the time his own top speed needs for the
    /// track — otherwise a 12-yard boot inside a 1.25 s drop teleports him at
    /// ~10 yd/s. Mirrors the run leg's clamp in `rushSteps`; capped so a long
    /// track can't stall the play, and never SHORTER than the called rhythm.
    private static func dropDuration(_ c: Context, steps: Int, path: RoutePath?) -> TimeInterval {
        let base = dropDuration(steps)
        guard let path, path.total > 0 else { return base }
        let sprint = TimeInterval(path.total / max(c.oSpeed(0), 0.1))
        return min(max(base, sprint), 2.6)
    }

    /// Where the QB throws from: the end of his DESIGNED rollout when the
    /// call draws him a track (a boot is a boot because he leaves the spot),
    /// else straight back at the called drop depth. The path is returned so
    /// the dropback step can run him through it instead of backpedalling.
    private static func launchSpot(_ c: Context, steps: Int)
        -> (path: RoutePath?, x: Float, z: Float) {
        let start = c.offense[0]
        if c.shape.qb == .rollout, let path = specPath(role: 0, c: c) {
            return (path, path.end.x, path.end.z)
        }
        return (nil, start.x, clampZ(start.z - c.direction * dropDepth(c, steps: steps)))
    }

    /// The passer's signature throwing motion for a pass, chosen from throw
    /// depth, coverage and a per-QB lean (his own speed nudges mobile passers
    /// toward the quick 3/4 flick). A deep ball drives (bullet) into tight
    /// coverage and floats (lob) when the man is open; a `forced` throw
    /// (undercut pick, pressured heave) comes off the back foot. Derived from
    /// deterministic sim inputs and built once per play — no per-frame flicker,
    /// pure presentation (the sim result is untouched).
    private static func throwStyle(_ c: Context, depth: Float,
                                   tight: Bool = false, forced: Bool = false)
        -> FootballFieldScene.ThrowStyle {
        if forced { return .offFoot }
        if depth >= 16 { return tight ? .bullet : .lob }
        if depth < 8 { return c.oSpeed(0) >= 8.2 ? .sidearm : .overhand }
        return .overhand
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
        // The QB keeps it when the sim named him (a scramble, and now every
        // designed keeper — `OffensivePlayCall.designedRusher` credits the
        // sneak / push / QB draw / option to the quarterback) and, as a
        // fallback for snaps the sim never attributed (two-point tries, older
        // saved plays), when the CALL itself is his.
        let designedKeeper = c.shape.qb == .keeper && c.spec.routes[0] != nil
        let isScramble = c.carrierRole == 0
            || designedKeeper
            || (c.carrierRole == nil && c.spec.carrierRole == 0)
        // The DESIGN decides who carries it when it names somebody other than
        // the back (an end around is the X receiver's play). The sim credits
        // the same man, so this agrees with `c.carrierRole` — it is the
        // fallback for an unattributed snap, not a second opinion.
        let designedCarrier = c.spec.carrierRole.flatMap { $0 > 1 ? $0 : nil }
        let carrierRole = isScramble ? 0 : (designedCarrier ?? 1)
        let carrier = c.oBase + carrierRole
        let carrierStart = c.offenseStart(carrierRole)
        let isDraw = c.call == .draw
        let isToss = c.shape.qb == .pitch
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
        // PRE-SNAP MOTION. The design's motion man crosses the formation
        // before the ball moves. When he is ALSO the carrier (end around), he
        // only gets PART of the way across at the snap and his run picks up
        // from exactly there — full-speed, going the other way, which is the
        // entire point of the play.
        let motionRole = c.spec.motionRole
        var motionHandoff: (x: Float, z: Float)? = nil
        var runShape = shape
        if let motionRole, motionRole == carrierRole, shape.pts.count > 1 {
            let atSnap: Float = 0.4
            let spot = shape.point(at: atSnap)
            motionHandoff = spot
            runShape = RoutePath(points: [spot] + shape.slice(from: atSnap, to: 1))
        }
        // Where the ball actually changes hands (the motion man is already
        // moving; everyone else takes it from his alignment).
        let meshOrigin: (x: Float, z: Float) =
            motionHandoff ?? (carrierStart.x, carrierStart.z)
        var track = fitTrack(runShape, endZ: endZ, direction: c.direction)
        // How the FRONT works this concept — flow, aiming point, puller, and
        // the blown assignment when the sim rolled one.
        let blocking = runBlocking(c, shape: runShape, carrierStart: meshOrigin)

        // Visible mesh-point handoff. On a hand-to-hand run (NOT a toss pitch,
        // a sold-dropback draw, or a QB keeper) the ball must change hands AT
        // the QB/RB mesh instead of teleporting to a far-away back. Splice a
        // mesh waypoint — a short fixed reach off the QB toward the back, so it
        // sits right beside/behind him — into the FRONT of the carrier's track,
        // then fire `.carry` exactly there. The point is derived from the two
        // ALREADY mirror-baked alignments (qbStart/carrierStart), so Plan B
        // REVERSE and the scene's lateralSign both flow through automatically;
        // `.carry` itself carries no coordinate and is immune to both.
        let isHandoff = !isScramble && !isToss && !isDraw
        var meshPoint: (x: Float, z: Float)? = nil
        var meshFraction: Float? = nil
        if isHandoff {
            let dx = meshOrigin.x - qbStart.x
            let dz = meshOrigin.z - qbStart.z
            let d = max((dx * dx + dz * dz).squareRoot(), 0.001)
            let meshRadius: Float = 0.85   // arm's-reach spacing (no capsule clip)
            let mesh = (x: clampX(qbStart.x + dx / d * meshRadius),
                        z: clampZ(qbStart.z + dz / d * meshRadius))
            track = RoutePath(points: [track.pts[0], mesh] + track.pts.dropFirst())
            meshPoint = mesh
            meshFraction = track.cum[1] / track.total
        }

        // Handoff timing along the track. A mesh run fires `.carry` exactly at
        // the spliced mesh (f1 = the mesh's arc fraction, so the transfer beat
        // == the RB's arrival beat) and takes a short beat past it before the
        // open-field run; the delayed draw holds the back until the dropback is
        // sold; toss/scramble keep their authored constants.
        let f1: Float
        let f2: Float
        if let meshFraction {
            f1 = meshFraction
            f2 = meshFraction + (1 - meshFraction) * 0.25
        } else {
            f1 = isDraw ? 0.06 : 0.14
            f2 = isDraw ? 0.3 : (isScramble ? 0.42 : 0.32)
        }

        // Breakaway runs flash 1-2 open-field moves; a juke also splices a
        // hard lateral jig into the track so the cut is real, not just a body
        // feint. Agile backs (high top speed) flash jukes/spins/dead-legs;
        // power backs truck through with stiff-arms and hurdles. A stable
        // per-carrier signature (his start spot + the sim's own gain) picks
        // WHICH move and WHICH way he jigs, so the same back shows the same
        // style, the roster stays varied, and nothing flickers frame to frame.
        // Matchup winners show off a second move. Pure presentation.
        let runGain = (endZ - c.losZ) * c.direction
        var openFieldPlan: [(kind: FootballFieldScene.OpenFieldMove.Kind, fraction: Float)] = []
        if runGain >= 12 {
            // `MatchupResolver.resolveRun` tags the carrier's own events with
            // the role the SIM credited, which is now the designed carrier —
            // so a keeper (role 0) and an end around (role 7) find their
            // flourish here instead of comparing against the back's role 1.
            let carrierWon = c.matchups?.events
                .contains { $0.offenseWon && $0.offRole == carrierRole } ?? false
            let two = runGain >= 22 || carrierWon
            let agile = c.oSpeed(carrierRole) >= 8.4
            let pool: [FootballFieldScene.OpenFieldMove.Kind] =
                agile ? [.juke, .spin, .deadLeg] : [.stiffArm, .hurdle, .juke]
            let sig = Int((abs(carrierStart.x) * 2 + runGain).rounded())
            let beats: [Float] = two ? [0.55, 0.82] : [0.62]
            for (index, fraction) in beats.enumerated() {
                let kind = pool[(sig + index) % pool.count]
                if kind == .juke {
                    track = jig(track, at: fraction, side: sig % 2 == 0 ? 1 : -1)
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

        // 0. Pre-snap motion: the design's motion man flies across the
        //    formation BEFORE the ball moves (jet, end around). A motion man
        //    who is also the carrier stops partway — he takes the ball on the
        //    move from there.
        if let motionRole, let motionPath = specPath(role: motionRole, c: c) {
            let spot = motionRole == carrierRole
                ? (motionHandoff ?? motionPath.point(at: 0.4))
                : motionPath.end
            stalkExclude.insert(c.oBase + motionRole)
            steps.append(Step(
                moves: [(c.oBase + motionRole, player(spot.x, spot.z), 0.9)],
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
        // The back who ISN'T carrying still has a job when the design drew him
        // one: the pitch man on an option, the pusher behind a sneak, the flow
        // fake on an end around. He runs it at his own speed.
        if carrierRole != 1, !stalkExclude.contains(c.rb),
           let path = specPath(role: 1, c: c) {
            stalkExclude.insert(c.rb)
            clearSlices += pathMoves(
                path, nodeIndex: c.rb,
                fractions: speedFractions(durations, total: path.total, speed: c.oSpeed(1)),
                durations: durations)
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
        } else if let meshPoint {
            // The QB opens toward the mesh and extends the ball to the back so
            // the exchange reads as a real hand-off. His chest ball rides his
            // hands every frame, so this half-step actually carries the ball to
            // the mesh — closing the visible gap — until step 2's `.carry`
            // re-parents it to the arriving back.
            snapScripted.append((c.qb,
                player(qbStart.x + (meshPoint.x - qbStart.x) * 0.5,
                       qbStart.z + (meshPoint.z - qbStart.z) * 0.5), snapDur))
        }
        let snapTaken = Set(snapPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                snapScripted,
                (sellsPass
                    ? pocketMoves(c, p: 0.6, d: snapDur)
                        + zoneMoves(c, plan: plan, p: 0.5, d: snapDur)
                    : lineSurgeMoves(c, p: 0.55, d: 0.55, dlShift: surgeShift * 0.4,
                                     blocking: blocking)
                        + routeMoves(c, p: 0.3, depthScale: 0.45, exclude: stalkExclude, d: 0.55)
                        + coverageMoves(c, mode: .run, p: 0.35, d: 0.55))
            ).filter { !snapTaken.contains($0.nodeIndex) },
            paths: snapPaths,
            ballMove: c.snapExchange,
            duration: snapDur,
            backpedals: snapBackpedals,
            blocks: lineBlockNodes(c),
            blockStyles: blockStyleMap(c, run: !sellsPass,
                                       beatenBlocker: blocking.bustedBlocker),
            startDelays: bustDelays(c, base: snapReactionDelays(c))
        ))

        // 2. Handoff (or the QB tucks it): the carrier hits the mesh on his
        //    track and the line battle resolves — winners visibly move the
        //    front. A toss flips the ball out to him in a little pitch arc.
        var meshPaths = clears(1)
        if let slice = carrierSlices[1] { meshPaths.append(slice) }
        let meshTaken = Set(meshPaths.map(\.nodeIndex))
        let meshBall: FootballFieldScene.BallMove = isToss
            ? .arc(to: air(track.point(at: f2).x, track.point(at: f2).z),
                   apex: 1.4, duration: meshDur * 0.85, from: c.qb)
            : .carry(nodeIndex: carrier)
        steps.append(Step(
            moves: merge(
                [],
                (sellsPass
                    ? pocketMoves(c, p: 1, d: meshDur)
                        + zoneMoves(c, plan: plan, p: 0.8, d: meshDur)
                    : lineSurgeMoves(c, p: 1, d: 0.55, dlShift: surgeShift, blocking: blocking)
                        + routeMoves(c, p: 0.6, depthScale: 0.45, exclude: stalkExclude, d: 0.55)
                        + coverageMoves(c, mode: .run, p: 0.7, d: 0.55))
            ).filter { !meshTaken.contains($0.nodeIndex) },
            paths: meshPaths,
            ballMove: meshBall,
            duration: meshDur,
            blocks: lineBlockNodes(c),
            blockStyles: blockStyleMap(c, run: !sellsPass,
                                       beatenBlocker: blocking.bustedBlocker)
        ))

        // 3. Run: the carrier finishes his track downfield; the credited
        //    defender leads the converge, the rest rally to the spot.
        let runDuration = runDur
        // R37: converge on the tackler the sim NAMED (feed/stat parity);
        // fall back to the matchup winner, then the middle backer.
        let tackler = c.matchups?.pickDefRole.map { c.dBase + $0 }
            ?? c.defenseWinnerRole.map { c.dBase + $0 }
            ?? c.lb(1)
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
                    + pursuitMoves(c, toX: endX, toZ: end.z, fraction: 0.75, d: runDuration)
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
            // A scrambling QB with room slides feet-first to protect himself
            // on a non-trivial gain rather than take the hit (deterministic).
            let slideQB = isScramble && carrier == c.qb && runGain >= 4 && runGain <= 14
                && hash01(carrier &* 51 &+ Int(runGain.rounded())) < 0.5
            if slideQB {
                steps.append(Step(moves: [], ballMove: .carry(nodeIndex: carrier),
                                  duration: 1.3, qbSlides: [carrier]))
            } else {
                steps += tackleSteps(c, carrier: carrier, tackler: tackler, x: endX, z: end.z)
            }
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
        // Deterministic variant selection: the same tackler in the same spot
        // gets the same "signature" hit, but the roster stays varied and
        // nothing flickers frame to frame (seed = who + where). Size class
        // (DL heavier than DB) tilts a stopped runner toward the blow-up.
        let seed = tackler &* 92821 &+ carrier &* 68917
            &+ Int(gain.rounded()) &* 40507 &+ Int(x.rounded()) &* 15486
        let roll = hash01(seed)
        let roll2 = hash01(seed &+ 777)
        let size: Float          // 0 = a DB … 1 = a lineman
        switch tacklerRole {
        case 0...3: size = 1        // DL
        case 4...6: size = 0.6      // LB
        default: size = 0.25        // CB / S
        }
        // Line to gain reached on this rep → the carrier reaches the ball out.
        let toGo = Float(c.play.distance)
        let reachedMarker = toGo > 0 && gain >= toGo - 0.5 && gain <= toGo + 2
        let markerLunge = reachedMarker ? [carrier] : []

        // BIG HIT: a stopped runner is blown backward off his feet — bigger
        // hitters land it more often.
        let bigHitChance = 0.18 + size * 0.45
        if c.defenseWinnerRole != nil, gain < 3, roll < bigHitChance {
            let backZ = clampZ(z - c.direction * (0.9 + hash01(seed &+ 5) * 0.4))
            let gang = gangTacklers(c, x: x, z: backZ, excluding: [tackler])
            return [Step(
                moves: [
                    (nodeIndex: carrier, to: player(x, backZ), duration: 0.3),
                    (nodeIndex: tackler, to: player(x + 0.3, backZ + c.direction * 0.3), duration: 0.3),
                ] + pileOnMoves(c, gang: gang, x: x, z: backZ),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.4,
                pulses: [tackler],
                falls: [tackler] + gang,
                bigHits: [carrier]
            )]
        }

        // DRAG-DOWN from behind on a breakaway: the tackler hauls the carrier
        // DOWN at the spot. The carrier is ARRESTED here (no forward slide — an
        // in-place hold-pose that slid forward read as "he keeps running through
        // the tackle"); the tackler drives in onto him from behind.
        if gain >= 12, roll < 0.6 {
            let gang = gangTacklers(c, x: x, z: z, excluding: [tackler])
            return [Step(
                moves: [
                    (nodeIndex: tackler, to: player(x + 0.25, z - c.direction * 0.2), duration: 0.4),
                ] + pileOnMoves(c, gang: gang, x: x, z: z),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.4,
                pulses: [tackler],
                falls: [carrier, tackler] + gang,
                wraps: [tackler],
                lunges: markerLunge
            )]
        }

        // DIVING TACKLE: the tackler closed from distance — a flat launch at
        // the carrier's legs cuts him down (carrier collapses forward).
        if approach > 12, roll < 0.7 {
            let gang = gangTacklers(c, x: x, z: z, excluding: [tackler])
            return [Step(
                moves: [(nodeIndex: tackler,
                         to: player(x + 0.2, z), duration: 0.25)]
                    + pileOnMoves(c, gang: gang, x: x, z: z),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.3,
                pulses: [tackler],
                falls: [carrier] + gang,
                diveFalls: [tackler],
                lunges: markerLunge
            )]
        }

        // SHOESTRING / ANKLE TACKLE: a short-range dive at the shoetops — the
        // carrier's legs are cut out and he stumbles forward onto the turf.
        // Quicker, smaller defenders throw it more than heavy linemen do.
        if gain <= 8, approach <= 12, roll2 < 0.24 + (1 - size) * 0.18 {
            let gang = gangTacklers(c, x: x, z: z, excluding: [tackler])
            return [Step(
                moves: [
                    (nodeIndex: tackler, to: player(x - 0.3, z - c.direction * 0.2), duration: 0.22),
                ] + pileOnMoves(c, gang: gang, x: x, z: z),
                ballMove: .carry(nodeIndex: carrier),
                duration: 1.3,
                pulses: [tackler],
                falls: gang,
                diveFalls: [tackler],
                trips: [carrier]
            )]
        }

        // WRAP-UP (default): the tackler DRIVES into the carrier and wraps him
        // up — the arms cinch BEFORE the pile hits the turf — then both go down
        // in the carrier's momentum direction; a harder rep (≈30%) first drives
        // him back half a yard. Gang chasers pile on staggered.
        var steps: [Step] = []
        let driveBack = hash01(seed &+ 313) < 0.3
        // Forward momentum carries the pile a touch downfield; a drive-back
        // shoves it back toward the LOS instead.
        // The common wrap goes DOWN at the spot (an in-place hold-pose that slid
        // forward read as the carrier "running through" the tackle); only a
        // drive-back shoves the pile back toward the LOS.
        let momentum: Float = driveBack
            ? -(0.5 + hash01(seed &+ 99) * 0.5)
            : 0
        let pileZ = clampZ(z + c.direction * momentum)
        // Contact: the tackler closes the last yard THROUGH the carrier from
        // his pursuit angle (a forward drive), arms wrapping as they collide —
        // and the carrier goes DOWN on THIS beat, the moment he's reached the
        // spot, exactly as every other hit in the library does. Falling him a
        // beat later (at the pile step) left his run clip looping in place at
        // the spot for 0.36s — his own contact move here is ~0 distance (pileZ
        // == his run destination on a non-drive-back rep) so it hit the
        // sub-0.4yd skip guard and never cleared `setMoving`, leaving him
        // jogging until the pile landed.
        // ONE continuous contact beat: the tackler drives THROUGH the carrier and
        // both go DOWN together, while the gang converges onto the same pile and each
        // man falls AS he lands (fall stagger by list order — carrier first, then the
        // tackler, then the chasers). No separate pile step a beat later, so there is
        // no window of men standing frozen over the carrier before a synchronized drop.
        let gang = gangTacklers(c, x: x, z: pileZ, excluding: [tackler])
        steps.append(Step(
            moves: [(nodeIndex: tackler, to: player(x + 0.3, pileZ + c.direction * 0.25), duration: 0.3)]
                + pileOnMoves(c, gang: gang, x: x, z: pileZ),
            ballMove: .carry(nodeIndex: carrier),
            duration: 0.6,
            pulses: [tackler],
            falls: [carrier, tackler] + gang,
            wraps: [tackler] + gang,
            lunges: markerLunge
        ))
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
        if c.shape.slowScreen {
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

        // QB mechanics from the CALL: the drop rhythm the concept is timed to,
        // the run fake it comes off, and the launch point (a boot leaves the
        // spot entirely — the throw then comes from wherever he rolled to).
        let fake: SnapFake = c.shape.rpo ? .rpoRide : (c.shape.playAction ? .playAction : .none)
        let dropCount = dropSteps(c, airDepth: airDepth)
        let deepDrop = dropCount >= 7
        let launch = launchSpot(c, steps: dropCount)
        let qbDropZ = launch.z
        // Physical pacing: the drop takes its real time and the ball flies at
        // ~18 yd/s from the launch point (20 air yards ≈ 1.1 s).
        let throwDX = catchSpot.x - launch.x
        let throwDZ = catchSpot.z - qbDropZ
        let throwDistance = (throwDX * throwDX + throwDZ * throwDZ).squareRoot()
        // R38 mech 3 (presentation): a stronger arm drives the ball faster, so
        // the flight is shorter; a weak arm floats it. nil = league average.
        let velocityScale = Float(c.play.passVelocityScale ?? 1.0)
        let flight = TimeInterval(min(max(throwDistance / (Self.passVelocity * velocityScale), 0.5), 1.5))
        let durations: [TimeInterval] = [snapBeat(fake),
                                         dropDuration(c, steps: dropCount, path: launch.path),
                                         flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: targetPath,
                                  durations: durations, qbDropZ: qbDropZ,
                                  qbDropX: launch.x, qbPath: launch.path)

        var steps: [Step] = []

        // 1-2. Snap and dropback: all five patterns release and stem, the
        //      coverage plays its call, the rush pushes the pocket. Deep
        //      shots pump-fake at the top of the drop ~30% of the time.
        steps.append(snapStep(c, frame: frame, fake: fake))
        steps.append(dropStep(c, frame: frame,
                              pumpFake: deepDrop && Float.random(in: 0..<1) < 0.3))

        // 3. Throw: the ball arcs to the catch point on the route while
        //    every other pattern and coverage path plays out underneath it;
        //    the nearest zone defender breaks on the ball in the air.
        let breaker = nearestZoneDefender(frame.plan, to: catchSpot, c: c)
        let apex = 3 + min(max(catchDepth, 0), 25) / 25 * 3
        let flightPaths = framePaths(frame, step: 2)
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        var flightMoves = zoneMoves(c, plan: frame.plan, p: 1,
                                    exclude: breaker.map { Set([c.dBase + $0]) } ?? [],
                                    d: flight)
        if let breaker {
            let side: Float = c.defense[breaker].x > catchSpot.x ? 1 : -1
            flightMoves.append((c.dBase + breaker,
                                player(catchSpot.x + side * 0.9, catchSpot.z + c.direction * 0.4),
                                flight))
        }
        // Nobody freezes while the ball is in the air: fill in continuation
        // moves for every node the paths/zones above didn't already cover.
        let flightCovered = flightTaken.union(flightMoves.map(\.nodeIndex))
        flightMoves += flightSupportMoves(c, frame: frame, ballSpot: (catchSpot.x, catchSpot.z),
                                          covered: flightCovered, d: flight)
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
        } else if tightCoverage && catchDepth >= 8 {
            catchStyle = .jump          // contested ball up the field — go UP and get it
        } else {
            catchStyle = .reach         // routine ball to the numbers — hands catch, turn to it
        }
        // A jump ball arrives HIGH (above the leaping receiver) on a steeper arc;
        // routine catches come in at chest height.
        let ballApex = catchStyle == .jump ? apex + 3 : apex
        let catchAir = catchStyle == .jump ? air(catchSpot.x, catchSpot.z, ballCarryY + 1.3)
                                           : air(catchSpot.x, catchSpot.z)
        let (blockNodes, blockStyles) = flightBlocks(c, frame: frame)
        steps.append(Step(
            moves: flightMoves.filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: catchAir, apex: ballApex, duration: flight, from: c.qb),
            duration: flight,
            reaches: [receiver],
            blocks: blockNodes,
            throwStyle: throwStyle(c, depth: catchDepth, tight: tightCoverage),
            catchStyles: [receiver: catchStyle],
            blockStyles: blockStyles
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
            // Receivers are open-field runners: burners juke/spin away, bigger
            // possession types dead-leg and stiff-arm through. Deterministic
            // per-catch signature so the man plays to type without flicker.
            let agile = c.oSpeed(receiverRole) >= 8.6
            let pool: [FootballFieldScene.OpenFieldMove.Kind] =
                agile ? [.juke, .spin, .deadLeg] : [.spin, .stiffArm, .deadLeg]
            let sig = Int((abs(catchSpot.x) * 2 + yacDistance).rounded())
            yacOpenField.append(.init(nodeIndex: receiver,
                                      kind: pool[sig % pool.count],
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
                ballMove: .arc(to: ground(screenSpot.x, screenSpot.z), apex: 1.6, duration: 0.5, from: c.qb),
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
            ballMove: .arc(to: air(screenSpot.x, screenSpot.z), apex: 1.8, duration: 0.5, from: c.qb),
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
        if c.shape.slowScreen {
            return screenSteps(c, endZ: c.losZ, complete: false).steps
        }
        // FIX-2: a rush-forced incompletion plays its OWN choreography — the
        // credited rusher beats his block and closes to the launch point, and
        // a deliberate throwaway sails to open space out of bounds. Gated OFF
        // for named coverage breakups (passBreakup) and plain misses so those
        // still run the generic in-pattern miss below.
        if c.play.pressured == true, c.play.passBreakup != true {
            return pressuredIncompletionSteps(c)
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

        let fake: SnapFake = c.shape.rpo ? .rpoRide : (c.shape.playAction ? .playAction : .none)
        let dropCount = dropSteps(c, airDepth: routeDepth)
        let deepDrop = dropCount >= 7
        let launch = launchSpot(c, steps: dropCount)
        let qbDropZ = launch.z
        // Real drop time + ball flight from the actual throw distance.
        let missDX = miss.x - launch.x
        let missDZ = miss.z - qbDropZ
        let missDistance = (missDX * missDX + missDZ * missDZ).squareRoot()
        let flight = TimeInterval(min(max(missDistance / Self.passVelocity, 0.55), 1.5))
        let durations: [TimeInterval] = [snapBeat(fake),
                                         dropDuration(c, steps: dropCount, path: launch.path),
                                         flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: route,
                                  durations: durations, qbDropZ: qbDropZ,
                                  qbDropX: launch.x, qbPath: launch.path)
        // A busted route is the one miss the receiver never chases: he broke it
        // off short (the frame already truncated him), and the ball sails to
        // the spot the play designed. No lunge — he isn't within ten yards.
        let routeBusted = c.bust?.kind == .route && c.bust?.offRole == receiverRole

        var steps: [Step] = []
        steps.append(snapStep(c, frame: frame, fake: fake))
        steps.append(dropStep(c, frame: frame,
                              pumpFake: deepDrop && Float.random(in: 0..<1) < 0.3))

        // Overthrown ball; the target finishes his route and lunges after it
        // while every other pattern and coverage path plays out.
        // The covering man contests the throw: the man on the target (else the
        // nearest zone defender to the miss point) breaks to the ball with a
        // hand up — same timing as a completion's breaker, but to the dead ball.
        let contester = frame.manOnTarget
            ?? nearestZoneDefender(frame.plan, to: (miss.x, miss.z), c: c)
        var flightPaths = framePaths(frame, step: 2,
            excludeNodes: routeBusted ? (contester.map { Set([c.dBase + $0]) } ?? [])
                : Set([receiver] + (contester.map { [c.dBase + $0] } ?? [])))
        if !routeBusted {
            var lungePoints = frame.routeSlices[receiverRole]?[2]?.points ?? []
            lungePoints.append(player(endPt.x + legDX / legLen * 1.0,
                                      endPt.z + legDZ / legLen * 1.0))
            flightPaths.append((receiver, lungePoints, flight))
        }
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        var flightMoves = zoneMoves(c, plan: frame.plan, p: 1,
            exclude: contester.map { Set([c.dBase + $0]) } ?? [], d: flight)
        var contestReaches: [Int] = routeBusted ? [] : [receiver]
        if let contester {
            let side: Float = c.defense[contester].x > miss.x ? 1 : -1
            flightMoves.append((c.dBase + contester,
                                player(clampX(miss.x + side * 0.8),
                                       clampZ(miss.z + c.direction * 0.3)), flight))
            contestReaches.append(c.dBase + contester)
        }
        // Nobody freezes while the ball is in the air.
        let flightCovered = flightTaken.union(flightMoves.map(\.nodeIndex))
        flightMoves += flightSupportMoves(c, frame: frame, ballSpot: (miss.x, miss.z),
                                          covered: flightCovered, d: flight)
        let (blockNodes, blockStyles) = flightBlocks(c, frame: frame)
        steps.append(Step(
            moves: flightMoves.filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: miss, apex: 4, duration: flight, from: c.qb),
            duration: flight,
            reaches: contestReaches,
            blocks: blockNodes,
            throwStyle: throwStyle(c, depth: routeDepth, forced: deepDrop),
            blockStyles: blockStyles
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

    /// FIX-2 — under-pressure incompletion. The CREDITED rusher beats his
    /// blocker and closes to the QB's launch point, arriving right as the ball
    /// comes out (no fall, no bury — the QB gets it off just before contact).
    /// On a deliberate throwaway the ball is a LOW flat heave to an
    /// out-of-bounds sideline point past the widest receiver, the receivers
    /// break off their routes, and no defender contests it. A hurried (non-
    /// throwaway) forced throw is a near-target miss with no accurate draped
    /// contest. Mirror-safe: the sideline is derived from the already-mirrored
    /// offense x and `direction`, never a raw constant.
    private static func pressuredIncompletionSteps(_ c: Context) -> [Step] {
        let receiverRole = targetRole(c)
        let route = specPath(role: receiverRole, c: c) ?? fallbackPath(role: receiverRole, c: c)
        let routeDepth = max(route.maxDepth(losZ: c.losZ, direction: c.direction), 1)

        let fake: SnapFake = c.shape.rpo ? .rpoRide : (c.shape.playAction ? .playAction : .none)
        let qbStart = c.offenseStart(0)
        let qbDropZ = clampZ(qbStart.z - c.direction
                             * dropDepth(c, steps: dropSteps(c, airDepth: routeDepth)))
        let launch = player(qbStart.x, qbDropZ)

        // The rusher who got home (MatchupResolver set rushWinnerDefRole on a
        // pressure), same side the pocket caves from — exactly like sackSteps.
        let rusherRole = c.matchups?.rushWinnerDefRole ?? 2
        let rusher = c.dl(rusherRole)
        let beaten = blockerFacing(defRole: rusherRole)

        let wasThrowaway = c.play.wasThrowaway == true

        // Ball destination.
        let target: SCNVector3
        let apex: Float
        if wasThrowaway {
            // Open space at the sideline on the FLOW side: the sign of the
            // widest eligible receiver's ALREADY-MIRRORED x, thrown past the
            // toe-tap line (~24, clampX-guarded to the field edge) into the
            // near flat. Correct under REVERSE (mirror) and away offense
            // (direction) with no raw constant.
            let widest = [7, 8, 9, 10, 1]
                .max(by: { abs(c.offense[$0].x) < abs(c.offense[$1].x) }) ?? 7
            let side: Float = c.offense[widest].x >= 0 ? 1 : -1
            target = air(clampX(side * 24), clampZ(c.losZ + c.direction * 5), 0.5)
            apex = 1.5
        } else {
            // Hurried near-target miss: past the route's break, no draped contest.
            let endPt = route.end
            let prevPt = route.pts.count >= 2 ? route.pts[route.pts.count - 2]
                : (x: endPt.x, z: endPt.z - c.direction)
            let legDX = endPt.x - prevPt.x
            let legDZ = endPt.z - prevPt.z
            let legLen = max((legDX * legDX + legDZ * legDZ).squareRoot(), 0.01)
            target = air(clampX(endPt.x + legDX / legLen * 2.0),
                         clampZ(endPt.z + legDZ / legLen * 2.0), 0.5)
            apex = 3
        }

        // Real pocket time: pressure gets home fast (pocketCollapse ~0.85 →
        // ~1.5 s), then a short ball flight from the launch point.
        let rushTime = TimeInterval(2.3 - c.pocketCollapse * 0.9)
        let missDX = target.x - launch.x
        let missDZ = target.z - launch.z
        let missDistance = (missDX * missDX + missDZ * missDZ).squareRoot()
        let flight = TimeInterval(min(max(missDistance / Self.passVelocity, 0.5), 1.3))
        let durations: [TimeInterval] = [snapBeat(fake), rushTime, flight]
        // A throwaway heaves to nobody: run every route full (no fitted target).
        let frame = dropbackFrame(c, targetRole: wasThrowaway ? nil : receiverRole,
                                  targetPath: wasThrowaway ? nil : route,
                                  durations: durations, qbDropZ: qbDropZ)

        // Shed-then-burst (mirrors sackSteps). The pressuring rusher GRINDS at
        // the line through the dropback, then SHEDS and BURSTS to the launch
        // point, bearing down just as the ball comes out — instead of one slow
        // drift then a last-yard creep. The burst window here is the ball
        // FLIGHT (not a fixed 0.8 s), so scale the reclaimed distance to it
        // (~6.5 yd/s) and clamp to the QB's actual drop depth. x's track the
        // ALREADY-MIRRORED beaten blocker / QB spot so REVERSE stays correct;
        // the burst stops a stride short of the throwing QB (no clip, no fall).
        let launchDepth = (c.losZ - launch.z) * c.direction
        let burstReach = min(max(Float(flight) * 6.5, 3.0), launchDepth)
        let engageDepth = max(launchDepth - burstReach, 1.4)
        let engageX = lerp(c.offense[beaten].x, launch.x, 0.3)
        let rusherEngage = player(engageX, c.losZ - c.direction * engageDepth)
        let rusherBurst = player(lerp(engageX, launch.x, 0.85), launch.z + c.direction * 0.6)

        var steps: [Step] = []

        // Snap: protection sets, all routes release, coverage plays its call.
        steps.append(snapStep(c, frame: frame, fake: fake))

        // Dropback while the credited rusher knifes through a pocket collapsing
        // from HIS side; the QB reaches his launch point. The credited rusher is
        // EXCLUDED from the coverage frame so his explicit shed-then-burst move
        // always wins — a blitzing LB the sim credited (rushWinnerDefRole 4–6)
        // then reliably reads as the man getting home rather than dropping into
        // his frame coverage assignment. For a DL rusher (0–3, never in the
        // coverage frame) this exclusion is a no-op.
        let dropPaths = framePaths(frame, step: 1, excludeNodes: [rusher])
        var taken = Set(dropPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: c.qb, to: launch, duration: rushTime),
                    (nodeIndex: rusher, to: rusherEngage, duration: rushTime),
                ],
                pocketMoves(c, p: 1, d: rushTime, beatenBlocker: beaten,
                            dropping: frame.plan.droppers)
                    + zoneMoves(c, plan: frame.plan, p: 0.9, d: rushTime)
            ).filter { !taken.contains($0.nodeIndex) },
            paths: dropPaths,
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: rushTime,
            backpedals: [c.qb],
            blocks: lineBlockNodes(c, dropping: frame.plan.droppers).filter { $0 != rusher },
            blockStyles: blockStyleMap(c, run: false, beatenBlocker: beaten)
        ))

        // Release: the ball comes out just as the rusher arrives at the launch
        // point — no fall, no bury. On a throwaway the receivers peel back and
        // relax (nobody chases an uncatchable ball); nobody contests it, so
        // their route paths are dropped this step in favor of the break-off.
        let receiverNodes: Set<Int> = wasThrowaway
            ? Set([1, 7, 8, 9, 10].map { c.oBase + $0 }) : []
        let flightPaths = framePaths(frame, step: 2, excludeNodes: receiverNodes.union([rusher]))
        taken = Set(flightPaths.map(\.nodeIndex))
        var flightMoves: [Move] = [
            (nodeIndex: rusher, to: rusherBurst, duration: flight),
        ]
        if wasThrowaway {
            for role in [1, 7, 8, 9, 10] {
                let idx = c.oBase + role
                guard !taken.contains(idx), let end = frame.routeEnds[role] else { continue }
                flightMoves.append((idx, player(lerp(end.x, qbStart.x, 0.15),
                                                end.z - c.direction * 1.5), flight))
            }
        }
        flightMoves += zoneMoves(c, plan: frame.plan, p: 1, d: flight)
        let flightCovered = taken.union(flightMoves.map(\.nodeIndex))
        flightMoves += flightSupportMoves(c, frame: frame, ballSpot: (target.x, target.z),
                                          covered: flightCovered, d: flight)
        let (blockNodes, blockStyles) = flightBlocks(c, frame: frame)
        steps.append(Step(
            moves: flightMoves.filter { !taken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: target, apex: apex, duration: flight, from: c.qb),
            duration: flight,
            blocks: blockNodes.filter { $0 != rusher },
            throwStyle: .offFoot,
            blockStyles: blockStyles
        ))

        // Ball dies — skittering out of bounds on a throwaway, dead on the turf
        // on a hurried miss. No advance.
        steps.append(Step(
            moves: [],
            ballMove: .slide(to: ground(target.x, target.z + c.direction * 1.5), duration: 0.5),
            duration: 0.6
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

        // Shed-then-burst. The credited rusher GRINDS at the line through the
        // whole dropback — locked with his beaten blocker a stride in front of
        // the sack (a short LOS fight, not a slow drift across open backfield) —
        // then SHEDS and BURSTS to the QB across the 0.8 s finish window at a
        // real closing speed. The engage point seats so the finish reclaims
        // ~`burstReach` yards (≈7 yd/s), i.e. sackSpot pulled back along the
        // rush; on a deep sack the engage sits deeper so phase A is a jog, not a
        // sprint. Both x's track the ALREADY-MIRRORED beaten blocker / QB spot
        // (never a raw lateral constant) so REVERSE shades the rush to the
        // correct side. Feet settle via the loco EMA, so the low-cadence grind
        // reads as planted rather than a creep-walk.
        let burstReach: Float = 5.5
        let engageDepth = max(sackDepth - burstReach, 1.4)
        let engageX = lerp(c.offense[beaten].x, sackSpot.x, 0.3)
        let rusherEngage = player(engageX, c.losZ - c.direction * engageDepth)
        let rusherBurst = player(lerp(engageX, sackSpot.x, 0.85), sackSpot.z)
        // Shallow sacks (sackYards 3-4) leave < 3yd between engage and the QB,
        // so a fixed 0.8s finish would replay the old creep-walk. Scale the
        // burst window to the actual distance (~7 yd/s) and give the leftover
        // time back to the grind phase — the bury beat stays put.
        let burstDist = hypot(rusherBurst.x - rusherEngage.x, rusherBurst.z - rusherEngage.z)
        let burstDur = min(0.8, max(0.35, TimeInterval(burstDist / 7.0)))
        let grindDur = rushTime + (0.8 - burstDur)

        var steps: [Step] = []

        // Snap: protection sets, all routes release, coverage plays its call.
        steps.append(snapStep(c, frame: frame,
                              fake: c.shape.playAction ? .playAction
                                  : (c.shape.rpo ? .rpoRide : .none)))

        // Dropback (backpedal) while the credited rusher knifes through a
        // pocket collapsing from HIS side — his blocker gets driven back.
        let dropPaths = framePaths(frame, step: 1)
        var taken = Set(dropPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [
                    (nodeIndex: c.qb, to: sackSpot, duration: grindDur),
                    (nodeIndex: rusher, to: rusherEngage, duration: grindDur),
                ],
                pocketMoves(c, p: 1, d: grindDur, beatenBlocker: beaten,
                            dropping: frame.plan.droppers)
                    + zoneMoves(c, plan: frame.plan, p: 0.9, d: grindDur)
            ).filter { !taken.contains($0.nodeIndex) },
            paths: dropPaths,
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: grindDur,
            backpedals: [c.qb],
            blocks: lineBlockNodes(c, dropping: frame.plan.droppers).filter { $0 != rusher },
            blockStyles: blockStyleMap(c, run: false, beatenBlocker: beaten)
        ))

        // Rusher closes the last yard; the patterns finish with nowhere to go.
        let finishPaths = framePaths(frame, step: 2)
        taken = Set(finishPaths.map(\.nodeIndex))
        steps.append(Step(
            moves: merge(
                [(nodeIndex: rusher, to: rusherBurst, duration: burstDur)],
                zoneMoves(c, plan: frame.plan, p: 1, d: burstDur * 0.94)
            ).filter { !taken.contains($0.nodeIndex) },
            paths: finishPaths,
            ballMove: .carryChest(nodeIndex: c.qb),
            duration: burstDur
        ))

        // Sack: the QB is buried; both hit the turf, the rusher wrapped
        // around him. A clearly open receiver signals what might have been.
        let openHands: [Int] = c.matchups?.openNonTargetOffRole
            .flatMap { [c.oBase + $0] } ?? []
        steps.append(Step(moves: [], ballMove: .carryChest(nodeIndex: c.qb), duration: 1.3,
                          pulses: [rusher], falls: [c.qb, rusher],
                          fallStyles: [c.qb: .sacked, rusher: .sackDrive],
                          wraps: [rusher], reaches: openHands))
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

        let fake: SnapFake = c.shape.rpo ? .rpoRide : (c.shape.playAction ? .playAction : .none)
        let dropCount = dropSteps(c, airDepth: routeDepth)
        let launch = launchSpot(c, steps: dropCount)
        let qbDropZ = launch.z
        // Real drop time + ball flight from the throw distance to the pick.
        let pickDX = pick.x - launch.x
        let pickDZ = pick.z - qbDropZ
        let pickDistance = (pickDX * pickDX + pickDZ * pickDZ).squareRoot()
        let flight = TimeInterval(min(max(pickDistance / Self.passVelocity, 0.55), 1.5))
        let durations: [TimeInterval] = [snapBeat(fake),
                                         dropDuration(c, steps: dropCount, path: launch.path),
                                         flight]
        let frame = dropbackFrame(c, targetRole: receiverRole, targetPath: route,
                                  durations: durations, qbDropZ: qbDropZ,
                                  qbDropX: launch.x, qbPath: launch.path)

        // The credited DB (else the man on the target, else the nearest zone
        // defender) is the one who jumps it.
        let dbRole = c.matchups?.pickDefRole
            ?? frame.manOnTarget
            ?? nearestZoneDefender(frame.plan, to: (pick.x, pick.z), c: c)
            ?? (route.pts[0].x < 0 ? 7 : 8)
        let db = c.dBase + dbRole

        var steps: [Step] = []
        steps.append(snapStep(c, frame: frame, fake: fake))
        steps.append(dropStep(c, frame: frame))

        // Throw sails to the undercut point: the DB drives on it while the
        // target finishes his break a step deep.
        let flightPaths = framePaths(frame, step: 2, excludeNodes: [db])
        let flightTaken = Set(flightPaths.map(\.nodeIndex))
        var flightMoves = merge(
            [(nodeIndex: db, to: pick, duration: flight)],
            zoneMoves(c, plan: frame.plan, p: 1, exclude: [db], d: flight)
        )
        // Nobody freezes while the ball is in the air.
        let flightCovered = flightTaken.union(flightMoves.map(\.nodeIndex))
        flightMoves += flightSupportMoves(c, frame: frame, ballSpot: (pick.x, pick.z),
                                          covered: flightCovered, d: flight)
        let (blockNodes, blockStyles) = flightBlocks(c, frame: frame)
        steps.append(Step(
            moves: flightMoves.filter { !flightTaken.contains($0.nodeIndex) },
            paths: flightPaths,
            ballMove: .arc(to: air(pick.x, pick.z), apex: 4.5, duration: flight, from: c.qb),
            duration: flight,
            reaches: [db, receiver],
            blocks: blockNodes,
            throwStyle: throwStyle(c, depth: routeDepth, forced: true),
            blockStyles: blockStyles
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

        // Goal-line run: the scorer lays out over the pylon with the ball
        // extended before he pops up to celebrate.
        let yardsToGoal = (c.direction * 50 - c.losZ) * c.direction
        if !passLike, yardsToGoal <= 6 {
            steps.append(Step(moves: [], ballMove: .carry(nodeIndex: script.carrier),
                              duration: 1.2, pylonDives: [script.carrier]))
        }

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
            ballMove: .arc(to: ground(script.end.x, script.end.z), apex: 3, duration: 0.6,
                           from: script.carrier),
            duration: 0.7
        ))

        return steps
    }

    // MARK: - Scripts: Special Teams

    /// Long snap to the punter → protection HOLDS while the gunners release →
    /// high arc downfield → basket catch (the punt-catch mocap) → a short
    /// escape weave → the gunners arrive first and wrap him up.
    private static func puntSteps(_ c: Context) -> [Step] {
        let punterSpot = c.offenseStart(0)  // formation already puts the QB 7yd back

        // Punt distance: use the sim's yardage when plausible, else 40.
        let reported = Float(c.play.yardsGained)
        let distance: Float = reported > 10 ? min(max(reported, 35), 45) : 40
        let landZ = clampZ(c.losZ + c.direction * distance)
        let returner = c.safety(0)
        let gunnerA = c.oBase + 7, gunnerB = c.oBase + 8   // outside releases

        // Boot phase. Real punt anatomy: the GUNNERS release at the snap and
        // beat the ball down; the interior EIGHT protect first (locked with
        // the rush), then peel and chase — arriving staggered and well behind
        // the gunners, not as one synchronized flood.
        let hang: TimeInterval = 2.1  // punt hang time (visual compromise)
        var bootMoves: [Move] = [(returner, player(0, landZ), hang)]
        var bootDelays: [Int: TimeInterval] = [:]
        for role in 1...10 {
            let start = c.offense[role]
            let isGunner = role == 7 || role == 8
            // Gunners land 2 yd short of the catch; the interior release wave
            // trails 10-16 yd behind, ragged by role.
            let depth: Float = isGunner ? 2 : 10 + hash01(role * 29 + 3) * 6
            bootMoves.append((c.oBase + role,
                              player(start.x * 0.85, clampZ(landZ - c.direction * depth)), hang))
            if !isGunner { bootDelays[c.oBase + role] = 0.55 }   // protect first, then peel
        }
        // Return unit: the interior shows a rush and stays LOCKED with the
        // protection through the hang (block engagements, not a backfield
        // drift); three men peel back late to wall off in front of the catch.
        var blocksList: [Int] = []
        var styles: [Int: FootballFieldScene.BlockStyle] = [:]
        let wallLanes: [Float] = [-5, 0, 5]
        var wallSlot = 0
        for role in 0..<11 where c.dBase + role != returner {
            let start = c.defense[role]
            if role < 6 {
                // Rush shows, gets absorbed by the shield — both sides engage.
                bootMoves.append((c.dBase + role,
                                  player(start.x, clampZ(lerp(start.z, c.losZ, 0.5))), 0.5))
                blocksList.append(c.dBase + role)
                styles[c.dBase + role] = .drive
            } else {
                // Wall men turn and get depth in front of the landing spot.
                let lane = wallLanes[wallSlot % wallLanes.count]; wallSlot += 1
                bootMoves.append((c.dBase + role,
                                  player(lane, clampZ(landZ - c.direction * 9)), hang))
                bootDelays[c.dBase + role] = 0.4
            }
        }
        // The protection shield is the engaged other half of those pairs.
        for role in 1...6 {
            blocksList.append(c.oBase + role)
            styles[c.oBase + role] = .anchor   // absorb the rush, give a little ground
        }

        // Catch → escape: the returner takes the basket catch, flashes one
        // escape move, and gets ~3 yd before the gunners swallow him.
        let returnEnd = player(1, landZ - c.direction * 3)
        let escape = [player(2.2, clampZ(landZ - c.direction * 1.2)),   // first step outside
                      returnEnd]                                        // hauled back in

        var steps: [Step] = []
        // Long snap slides back to the punter.
        steps.append(Step(
            moves: [],
            ballMove: .slide(to: ground(punterSpot.x, punterSpot.z), duration: 0.5),
            duration: 0.6,
            sound: .snap
        ))
        // Boot: gunners fly, the lines stay locked, the wall peels late and
        // the returner settles under it for a basket catch (catch_e — the
        // punt-catch mocap: look up, hands high, secure to the chest).
        steps.append(Step(
            moves: bootMoves,
            ballMove: .arc(to: air(0, landZ), apex: 12, duration: hang, from: nil),
            duration: hang,
            reaches: [returner],
            blocks: blocksList,
            kicker: c.oBase,   // the punter boots it
            catchStyles: [returner: .overShoulder],
            blockStyles: styles,
            startDelays: bootDelays,
            sound: .kickPunt
        ))
        // Catch and the short return: one juke feint off the catch while the
        // gunners close; the trailing release wave keeps coming but arrives
        // a beat too late to matter.
        var rallyMoves: [Move] = [
            (gunnerA, player(returnEnd.x - 1.0, returnEnd.z - c.direction * 1.0), 0.85),
            (gunnerB, player(returnEnd.x + 1.4, returnEnd.z + c.direction * 0.8), 0.95),
        ]
        for role in 1...10 where role != 7 && role != 8 {
            let start = c.offense[role]
            rallyMoves.append((c.oBase + role,
                               player(lerp(start.x * 0.85, returnEnd.x, 0.4),
                                      clampZ(landZ - c.direction * (5 + hash01(role * 11) * 4))), 1.0))
        }
        steps.append(Step(
            moves: rallyMoves,
            paths: [(returner, escape, 1.0)],
            ballMove: .carry(nodeIndex: returner),
            duration: 1.0,
            openField: [FootballFieldScene.OpenFieldMove(nodeIndex: returner, kind: .juke,
                                                         delay: 0.3)]
        ))
        // The gunners wrap him up — a real tackle finish, not a stand-around.
        steps.append(Step(
            moves: [],
            ballMove: .carry(nodeIndex: returner),
            duration: 1.1,
            pulses: [gunnerA],
            falls: [returner, gunnerA, gunnerB],
            wraps: [gunnerA]
        ))
        return steps
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
                ballMove: .arc(to: SCNVector3(clampX(targetX), targetY, postZ), apex: 8, duration: 1.6, from: nil),
                duration: 1.7,
                sound: .kickPlace
            ),
            Step(moves: [], ballMove: nil, duration: 0.45),
        ]
    }

    // MARK: - Scripts: Kickoffs

    /// World Z of the kicking tee (the kicking team's own 35-yard line).
    static func kickoffSpotZ(kickingTeamIsHome: Bool) -> Float {
        kickingTeamIsHome ? -15 : 15
    }

    /// Kicking team layout in node-role order: 0 = kicker in his run-up at the
    /// tee, 1-10 = the coverage line up on the RECEIVING team's 40 — the
    /// dynamic-kickoff alignment: both walls stand 5 yards apart downfield,
    /// nobody but the kicker near the tee.
    private static func kickoffKickingPositions(kickDir: Float) -> [(x: Float, z: Float, number: Int)] {
        let teeZ = -kickDir * 15
        let coverageZ = kickDir * 10   // receiving team's 40-yard line
        let lanes: [Float] = [-22, -17.5, -13, -8.5, -4, 4, 8.5, 13, 17.5, 22]
        let numbers = [41, 45, 52, 38, 29, 31, 47, 55, 44, 26]
        var out: [(x: Float, z: Float, number: Int)] = [(0, teeZ - kickDir * 6, 3)]
        for (i, x) in lanes.enumerated() {
            out.append((x, coverageZ, numbers[i]))
        }
        return out.map { (clampX($0.x), clampZ($0.z), $0.number) }
    }

    /// Receiving team layout in node-role order: 0-4 = front wall at their own
    /// 35 (the setup zone, nose to nose with the coverage), 5-8 = second wave
    /// at their 31, 9 = upback/escort, 10 = deep returner at the goal line.
    private static func kickoffReceivingPositions(kickDir: Float) -> [(x: Float, z: Float, number: Int)] {
        // Receiving team's own yard Y -> world z.
        func ownYard(_ y: Float) -> Float { kickDir * (50 - y) }
        var out: [(x: Float, z: Float, number: Int)] = []
        let frontX: [Float] = [-16, -8, 0, 8, 16]
        let frontNumbers = [58, 63, 72, 68, 77]
        for (i, x) in frontX.enumerated() { out.append((x, ownYard(35), frontNumbers[i])) }
        let waveX: [Float] = [-12, -4, 4, 12]
        let waveNumbers = [35, 27, 49, 42]
        for (i, x) in waveX.enumerated() { out.append((x, ownYard(31), waveNumbers[i])) }
        out.append((-2, ownYard(12), 22)) // upback escort
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
        let upback = rBase + 9
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

        // 2. Boot. Dynamic-kickoff rule: NOBODY but the kicker and the
        //    returner moves while the ball is in the air — both walls stand
        //    frozen five yards apart and the whole play erupts at the catch.
        //    (The old float, where all 20 lerped downfield under the flight,
        //    read as "everyone drifts, then the returner jogs into a line".)
        let hang: TimeInterval = 2.4  // real kickoff hang time
        steps.append(Step(
            moves: [(returner, player(0, catchZ), hang)],
            ballMove: .arc(to: air(0, catchZ), apex: 16, duration: hang, from: nil),
            duration: hang,
            reaches: [returner],
            kicker: kBase,   // the kickoff specialist swings through the tee
            sound: .kickPlace
        ))

        if isTouchback {
            // 3. Dead ball the instant it sails into the end zone: the walls
            //    relax where they stand (a step of drift, no release, no
            //    pursuit) and the returner settles with it. The view plays
            //    the whistle + "Touchback" banner on completion.
            var settle: [Move] = []
            for i in 1...10 {
                settle.append((kBase + i, player(kicking[i].x, kicking[i].z + kickDir * 1.2), 0.8))
            }
            steps.append(Step(moves: settle, ballMove: .carry(nodeIndex: returner), duration: 0.9))
            return steps
        }

        // 3. THE ERUPTION (catch -> first contact). Coverage releases down its
        //    lanes, the two return walls fit onto them man for man, the upback
        //    turns into the escort, and the returner takes his first burst.
        //    Two middle-lane coverage men are deliberately left UNBLOCKED —
        //    they become the pursuit (real returns die because somebody runs
        //    free, not because the returner jogs into a standing line).
        let chargeDur: TimeInterval = 1.3   // ~9 yd/s eruption, not warp speed
        let tacklerA = kBase + 5     // free runners in the middle lanes
        let tacklerB = kBase + 6
        let engageZ = ownYard(28)    // where the walls meet the coverage
        let blockedCoverage = [1, 2, 3, 4, 7, 8, 9, 10]
        let blockers = [rBase + 0, rBase + 1, rBase + 2, rBase + 3,
                        rBase + 5, rBase + 6, rBase + 7, rBase + 8]
        var engageX: [Int: Float] = [:]   // coverage role -> engagement x
        var charge: [Move] = []
        for (slot, cov) in blockedCoverage.enumerated() {
            let blocker = blockers[slot]
            let x = lerp(kicking[cov].x, receiving[blocker - rBase].x, 0.55)
            let jitter = (hash01(cov * 13 + 5) - 0.5) * 2.4   // ragged front
            engageX[cov] = x
            charge.append((kBase + cov, player(x, engageZ + kickDir * (1.0 + jitter)), chargeDur))
            charge.append((blocker, player(x, engageZ - kickDir * 0.9 + kickDir * jitter * 0.4), chargeDur))
        }
        charge.append((tacklerA, player(-3, ownYard(29)), chargeDur))
        charge.append((tacklerB, player(4.5, ownYard(28)), chargeDur))
        charge.append((kBase, player(0, -kickDir * 5), chargeDur))           // kicker = safety, trails
        charge.append((returner, player(1.5, ownYard(9)), chargeDur))        // first burst
        charge.append((upback, player(-1.5, ownYard(13)), chargeDur))        // escort turns
        steps.append(Step(moves: charge, ballMove: .carry(nodeIndex: returner), duration: chargeDur))

        // 4. THE RETURN. The walls lock up (real block engagements grinding
        //    downfield) while the returner WEAVES through the traffic —
        //    outside press, cut back inside, then downhill — flashing
        //    open-field moves at the cuts; the free runners pursue on angles
        //    to the spot the engine picked.
        let endYard: Float = isReturnTouchdown ? 102 : Float(returnYardLine)
        let endZ = clampZ(ownYard(endYard))
        let endX: Float = isReturnTouchdown ? 10 : 3
        let weaveStartZ = ownYard(9)
        let runDistance = abs(endZ - weaveStartZ)
        // Covered at a returner's sprint (~9 yd/s), not warp speed.
        let runDuration = TimeInterval(min(max(runDistance / 9.0, 1.4), 4.0))
        // Weave amplitude scales with the run so a short return doesn't zigzag
        // in place; fractions keep the shape on any return length.
        let amp = min(5.5, max(1.5, runDistance * 0.28))
        func wz(_ t: Float) -> Float { weaveStartZ + (endZ - weaveStartZ) * t }
        let weave = [player(amp, wz(0.30)),           // press outside
                     player(-amp * 0.45, wz(0.58)),   // cut back through the wall
                     player(endX, wz(1.0))]           // downhill to the spot
        var returnMoves: [Move] = []
        var blocksList: [Int] = []
        var styles: [Int: FootballFieldScene.BlockStyle] = [:]
        for (slot, cov) in blockedCoverage.enumerated() {
            let blocker = blockers[slot]
            blocksList += [kBase + cov, blocker]
            styles[blocker] = .drive        // wall holds and grinds...
            styles[kBase + cov] = .anchor   // ...coverage fights, gives ground
            let x = engageX[cov] ?? kicking[cov].x
            returnMoves.append((kBase + cov, player(x, engageZ + kickDir * 2.2), runDuration))
            returnMoves.append((blocker, player(x, engageZ + kickDir * 1.4), runDuration))
        }
        if isReturnTouchdown {
            // Housed: the pursuit takes bad angles and trails the burst.
            returnMoves.append((tacklerA, player(endX - 4, clampZ(wz(0.8))), runDuration))
            returnMoves.append((tacklerB, player(endX - 7, clampZ(wz(0.65))), runDuration))
        } else {
            // Pursuit angles meet the returner at the engine's spot.
            returnMoves.append((tacklerA, player(endX - 1.2, endZ - kickDir * 1.5), runDuration))
            returnMoves.append((tacklerB, player(endX + 1.8, endZ + kickDir * 1.0), runDuration))
        }
        // Upback escorts a stride ahead of the weave; kicker stays the last man.
        returnMoves.append((upback, player(endX - 2.5, clampZ(wz(0.75))), runDuration))
        returnMoves.append((kBase, player(endX * 0.4, clampZ(ownYard(min(endYard + 12, 46)))), runDuration))
        // Open-field moves at the cuts (the new mocap juke pair) — skipped on
        // a stuffed short return where there's no room to set one up.
        var openField: [FootballFieldScene.OpenFieldMove] = []
        if runDistance >= 10 {
            let second: FootballFieldScene.OpenFieldMove.Kind =
                hash01(returnYardLine * 17 + 3) < 0.5 ? .deadLeg : .spin
            openField = [
                FootballFieldScene.OpenFieldMove(nodeIndex: returner, kind: .juke,
                                                 delay: runDuration * 0.30),
                FootballFieldScene.OpenFieldMove(nodeIndex: returner, kind: second,
                                                 delay: runDuration * 0.58),
            ]
        }
        steps.append(Step(
            moves: returnMoves,
            paths: [(returner, weave, runDuration)],
            ballMove: .carry(nodeIndex: returner),
            duration: runDuration,
            pulses: isReturnTouchdown ? [returner] : [],
            blocks: blocksList,
            blockStyles: styles,
            openField: openField
        ))

        if isReturnTouchdown {
            // Breakaway finish: leap + pulse in the end zone (the view runs
            // the camera push and confetti).
            steps.append(Step(moves: [], ballMove: .carry(nodeIndex: returner),
                              duration: 0.6, pulses: [returner], celebrates: [returner]))
        } else {
            // 5. The pursuit arrives: the first free runner wraps, the second
            //    cleans up from the far side a beat later.
            steps.append(Step(
                moves: [(tacklerA, player(endX - 0.4, endZ - kickDir * 0.4), 0.4),
                        (tacklerB, player(endX + 0.6, endZ + kickDir * 0.4), 0.5)],
                ballMove: .carry(nodeIndex: returner),
                duration: 1.2,
                pulses: [tacklerA],
                falls: [returner, tacklerA, tacklerB],
                wraps: [tacklerA]
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
                 blockStyles: blockStyleMap(c, run: true),
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
