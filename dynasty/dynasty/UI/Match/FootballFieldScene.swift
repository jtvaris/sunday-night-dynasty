import SceneKit

// MARK: - Football Field Scene

/// A SceneKit scene that renders a complete NFL football field for the match view.
/// Designed for an elevated top-down camera angle suitable for a management game.
///
/// Coordinate system:
/// - X axis = sideline to sideline (width)
/// - Z axis = end zone to end zone (length)
/// - Y axis = up
/// - 1 unit = 1 yard
/// - Field centered at origin
class FootballFieldScene: SCNScene {

    // MARK: - Constants

    private enum FieldConstants {
        static let fieldLength: Float = 100       // 100 yards of playing field
        static let totalLength: Float = 120       // Including both 10-yard end zones
        static let fieldWidth: Float = 53.3333
        static let endZoneDepth: Float = 10
        static let yardLineWidth: Float = 0.1     // Thickness of yard lines
        static let hashMarkLength: Float = 0.6
        static let hashMarkWidth: Float = 0.1
        // NFL hash mark positions: 23.58 yards from each sideline
        static let hashInset: Float = 23.5833
        static let fieldThickness: Float = 0.2
        static let playerHeight: Float = 1.0
        static let playerRadius: Float = 0.4
        static let ballLength: Float = 0.7
        static let ballRadius: Float = 0.22
    }

    // MARK: - Colors

    private enum FieldColors {
        static let grass = UIColor(red: 0.11, green: 0.32, blue: 0.12, alpha: 1.0)
        static let endZone = UIColor(red: 0.07, green: 0.22, blue: 0.08, alpha: 1.0)
        static let yardLine = UIColor.white
        static let numbers = UIColor(white: 1.0, alpha: 0.85)
        static let sideline = UIColor.white
        static let fieldBorder = UIColor(red: 0.05, green: 0.16, blue: 0.06, alpha: 1.0)
    }

    // MARK: - Play Timeline Types

    /// One beat of a play sequence. All `moves` start simultaneously when the
    /// step begins; the step lasts `max(duration, longest move/ball duration)`
    /// before the next step starts.
    struct PlayStep {
        /// Player movements: `nodeIndex` 0-10 = home players, 11-21 = away players.
        var moves: [(nodeIndex: Int, to: SCNVector3, duration: TimeInterval)]
        /// Optional ball behavior for this step.
        var ballMove: BallMove?
        /// Minimum length of the step in seconds.
        var duration: TimeInterval
        /// Player nodes to pulse (brief scale-up) when the step begins.
        var pulses: [Int] = []
        /// Player nodes that go to the ground when the step begins (tackles).
        var falls: [Int] = []
        /// Player nodes that throw their arms up when the step begins (catches).
        var reaches: [Int] = []
        /// Player nodes whose moves this step are backpedals: they keep facing
        /// downfield while moving backwards (QB dropbacks).
        var backpedals: [Int] = []
        /// Player nodes that leap into a touchdown celebration this step.
        var celebrates: [Int] = []
    }

    /// How the ball behaves during a `PlayStep`.
    enum BallMove {
        /// Ball rides with the given player node (0-10 home, 11-21 away).
        case carry(nodeIndex: Int)
        /// Ball flies a parabolic arc to the target with the given apex height.
        case arc(to: SCNVector3, apex: Float, duration: TimeInterval)
        /// Ball moves flat along the ground (snaps, rolls, dead balls).
        case slide(to: SCNVector3, duration: TimeInterval)
    }

    // MARK: - Uniforms

    /// A full NFL-convention uniform: jersey, pants, and helmet colors.
    struct Uniform {
        var jersey: UIColor
        var pants: UIColor
        var helmet: UIColor

        /// Home teams wear their color; road teams wear white with team-color
        /// pants and helmet — instant NFL reading and guaranteed contrast.
        /// Helmets run a shade darker than the jersey so heads read as gear.
        static func home(teamColor: UIColor) -> Uniform {
            Uniform(jersey: teamColor,
                    pants: UIColor(white: 0.88, alpha: 1),
                    helmet: shaded(teamColor))
        }

        static func away(teamColor: UIColor) -> Uniform {
            Uniform(jersey: UIColor(white: 0.93, alpha: 1),
                    pants: teamColor,
                    helmet: shaded(teamColor))
        }

        private static func shaded(_ color: UIColor) -> UIColor {
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: max(r - 0.2, 0), green: max(g - 0.2, 0),
                           blue: max(b - 0.2, 0), alpha: a)
        }
    }

    // MARK: - Properties

    private(set) var cameraNode: SCNNode = SCNNode()
    private var cameraTargetNode: SCNNode = SCNNode()
    private var homePlayerNodes: [SCNNode] = []
    private var awayPlayerNodes: [SCNNode] = []
    private var ballNode: SCNNode = SCNNode()
    private var homeColor: UIColor = UIColor.blue
    private var awayColor: UIColor = UIColor.red
    private var homeUniform = Uniform.home(teamColor: .blue)
    private var awayUniform = Uniform.away(teamColor: .red)
    private var homeEndZoneNode: SCNNode?
    private var awayEndZoneNode: SCNNode?
    private var losMarkerNode = SCNNode()
    private var firstDownMarkerNode = SCNNode()
    /// Node index currently carrying the ball (for the arm-tuck pose).
    private var carryingIndex: Int?
    /// Camera's current focus Z, so the follow-cam can decide when to pan.
    private var focusZ: Float = 0
    /// While true the kick camera owns the shot: the follow-cam in `execute`
    /// stays parked so the ball arcs toward the lens. Any `focusCamera` call
    /// hands the shot back.
    private var kickCameraActive = false
    /// Incremented on every runPlay/cancelPlay so stale scheduled steps become no-ops.
    private var playGeneration = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupField()
    }

    // MARK: - Public API

    /// Builds the entire field, camera, lighting, and ball. Called automatically on init.
    func setupField() {
        // Clear any existing nodes
        rootNode.childNodes.forEach { $0.removeFromParentNode() }
        homePlayerNodes.removeAll()
        awayPlayerNodes.removeAll()

        buildFieldSurface()
        buildMowingStripes()
        buildEndZones()
        buildYardLines()
        buildNumbers()
        buildHashMarks()
        buildSidelines()
        buildGoalposts()
        buildPylons()
        buildApronWalls()
        buildMarkers()
        buildBall()
        buildCamera()
        buildLighting()

        // Depth falloff: the far field darkens into the night like a
        // low-slung TV camera shot.
        fogColor = UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        fogStartDistance = 80
        fogEndDistance = 210
        fogDensityExponent = 1.4
    }

    /// Sets the home team uniform color and updates existing player nodes.
    func setHomeTeamColor(_ color: UIColor) {
        homeColor = color
        homeUniform = Uniform.home(teamColor: color)
        homePlayerNodes.forEach { applyUniform(homeUniform, to: $0) }
    }

    /// Sets the away team uniform color and updates existing player nodes.
    func setAwayTeamColor(_ color: UIColor) {
        awayColor = color
        awayUniform = Uniform.away(teamColor: color)
        awayPlayerNodes.forEach { applyUniform(awayUniform, to: $0) }
    }

    /// Full NFL-convention uniforms (jersey / pants / helmet per side).
    func setUniforms(home: Uniform, away: Uniform) {
        homeUniform = home
        awayUniform = away
        homeColor = home.jersey
        awayColor = away.jersey
        homePlayerNodes.forEach { applyUniform(home, to: $0) }
        awayPlayerNodes.forEach { applyUniform(away, to: $0) }
    }

    /// Re-tints a figure by material slot name. Both the Blender kit parts
    /// and the procedural fallback name their materials JERSEY/PANTS/HELMET,
    /// and each figure owns per-figure copies of those materials (torso +
    /// arms share one JERSEY instance, legs one PANTS instance), so setting
    /// the diffuse here re-tints the whole figure without leaking into the
    /// other team. SKIN/MASK/SHOE materials are left untouched.
    private func applyUniform(_ uniform: Uniform, to node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                switch material.name {
                case "JERSEY": material.diffuse.contents = uniform.jersey
                case "PANTS": material.diffuse.contents = uniform.pants
                case "HELMET": material.diffuse.contents = uniform.helmet
                default: break
                }
            }
        }
    }

    /// Places 11 home and 11 away players at specified positions with jersey numbers.
    /// Coordinates are in yards from center of field.
    func positionPlayers(home: [(x: Float, z: Float, number: Int)],
                         away: [(x: Float, z: Float, number: Int)]) {
        // Remove old players
        homePlayerNodes.forEach { $0.removeFromParentNode() }
        awayPlayerNodes.forEach { $0.removeFromParentNode() }
        homePlayerNodes.removeAll()
        awayPlayerNodes.removeAll()

        // Spawn each side facing the other across the LOS.
        let homeAvgZ = home.map(\.z).reduce(0, +) / Float(max(home.count, 1))
        let awayAvgZ = away.map(\.z).reduce(0, +) / Float(max(away.count, 1))
        let homeYaw: Float = awayAvgZ >= homeAvgZ ? 0 : .pi
        let awayYaw: Float = homeYaw == 0 ? .pi : 0

        for info in home {
            let node = makePlayerNode(uniform: homeUniform, number: info.number)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            node.eulerAngles = SCNVector3(0, homeYaw, 0)
            rootNode.addChildNode(node)
            homePlayerNodes.append(node)
        }

        for info in away {
            let node = makePlayerNode(uniform: awayUniform, number: info.number)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            node.eulerAngles = SCNVector3(0, awayYaw, 0)
            rootNode.addChildNode(node)
            awayPlayerNodes.append(node)
        }
    }

    /// Moves the football to a position on the field.
    func moveBall(to position: SCNVector3) {
        let action = SCNAction.move(to: position, duration: 0.3)
        action.timingMode = .easeInEaseOut
        ballNode.runAction(action)
    }

    /// Animates a sequence of player movements for a play.
    /// `nodeIndex` 0-10 = home players, 11-21 = away players.
    func animatePlay(playerMoves: [(nodeIndex: Int, to: SCNVector3, duration: TimeInterval)]) {
        for move in playerMoves {
            let allPlayers = homePlayerNodes + awayPlayerNodes
            guard move.nodeIndex >= 0, move.nodeIndex < allPlayers.count else { continue }
            let node = allPlayers[move.nodeIndex]
            let action = SCNAction.move(to: move.to, duration: move.duration)
            action.timingMode = .easeInEaseOut
            node.runAction(action)
        }
    }

    /// Resets players to a default kickoff-style formation.
    func resetFormation() {
        let homePositions: [(x: Float, z: Float, number: Int)] = [
            (0, -15, 12),       // QB
            (-5, -17, 26),      // RB
            (-15, -14, 81),     // WR left
            (15, -14, 88),      // WR right
            (-8, -14, 84),      // WR slot left
            (8, -14, 87),       // WR slot right
            (-3, -14, 72),      // LT
            (-1.5, -14, 66),    // LG
            (0, -14, 55),       // C
            (1.5, -14, 64),     // RG
            (3, -14, 75),       // RT
        ]

        let awayPositions: [(x: Float, z: Float, number: Int)] = [
            (0, -11, 99),       // DT
            (-3, -11, 93),      // DE left
            (3, -11, 91),       // DE right
            (-7, -10, 56),      // LB left
            (0, -10, 52),       // MLB
            (7, -10, 54),       // LB right
            (-15, -8, 24),      // CB left
            (15, -8, 21),       // CB right
            (-5, -5, 33),       // SS
            (5, -5, 31),        // FS
            (8, -10, 48),       // Nickel
        ]

        positionPlayers(home: homePositions, away: awayPositions)
    }

    // MARK: - Pre-Snap Stances

    /// Position-appropriate pre-snap poses. `movePlayersToFormation` eases a
    /// player into his stance once he arrives at his spot; the stance breaks
    /// automatically at the snap when `run` starts his first play move.
    enum Stance {
        /// Deep lineman crouch with the down hand on the turf (OL/DL).
        case threePoint
        /// Knees-bent crouch, hands resting near the knees (RB/LB/S).
        case twoPoint
        /// Upright receiver/corner split stance: staggered feet, slight lean.
        case split
        /// Standing tall (QB, special-teams units).
        case upright
    }

    /// Smoothly moves the existing player nodes into a new formation instead of
    /// destroying and recreating them. Falls back to a full rebuild when the
    /// player counts differ. Jersey numbers on existing nodes are updated in
    /// place, and each player settles into his position's pre-snap stance
    /// (keyed by per-team node index; missing = upright).
    func movePlayersToFormation(home: [(x: Float, z: Float, number: Int)],
                                away: [(x: Float, z: Float, number: Int)],
                                duration: TimeInterval = 0.8,
                                stancesHome: [Int: Stance] = [:],
                                stancesAway: [Int: Stance] = [:]) {
        guard homePlayerNodes.count == home.count,
              awayPlayerNodes.count == away.count,
              !home.isEmpty || !away.isEmpty else {
            positionPlayers(home: home, away: away)
            return
        }

        // Once set, each side squares up toward the other across the LOS.
        let homeAvgZ = home.map(\.z).reduce(0, +) / Float(max(home.count, 1))
        let awayAvgZ = away.map(\.z).reduce(0, +) / Float(max(away.count, 1))
        let homeYaw: Float = awayAvgZ >= homeAvgZ ? 0 : .pi
        let awayYaw: Float = homeYaw == 0 ? .pi : 0

        for (offset, pair) in zip(homePlayerNodes + awayPlayerNodes, home + away).enumerated() {
            let (node, info) = pair
            let target = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            run(node: node, to: target, duration: duration, key: "formationMove")
            updateJerseyNumber(on: node, to: info.number)

            let isHomeNode = offset < homePlayerNodes.count
            let settleYaw = isHomeNode ? homeYaw : awayYaw
            let settle = SCNAction.sequence([
                SCNAction.wait(duration: duration),
                SCNAction.rotateTo(x: 0, y: CGFloat(settleYaw), z: 0, duration: 0.25, usesShortestUnitArc: true),
            ])
            node.runAction(settle, forKey: "settleFacing")

            // Everyone drops into his stance once he arrives at the line
            // (upright is applied too — it resets any previous stance).
            let stance = isHomeNode
                ? (stancesHome[offset] ?? .upright)
                : (stancesAway[offset - homePlayerNodes.count] ?? .upright)
            applyStance(stance, to: node, delay: duration + 0.2)
        }
    }

    /// Eases a figure into `stance` after `delay` (the formation travel time).
    /// Limb poses run under the same "swing"/"bend" keys the run cycle uses,
    /// so the next `swingLimbs` at the snap replaces them seamlessly; the
    /// figure pitch/sink runs under "stance", which `run` clears on takeoff.
    private func applyStance(_ stance: Stance, to node: SCNNode, delay: TimeInterval) {
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }

        // figure pitch (forward lean) + sink toward the turf, and per-limb
        // targets: (limb name, hinge x, hinge z, joint bend x).
        let pitch: CGFloat
        let sink: Float
        let limbs: [(name: String, x: CGFloat, z: CGFloat, joint: CGFloat)]
        switch stance {
        case .threePoint:
            // Deep crouch, right hand down on the turf, off arm on the knee,
            // legs staggered and loaded.
            pitch = 0.62; sink = -0.17
            limbs = [
                ("armR", 0.95, -0.12, 0.1),
                ("arm", 0.5, 0.3, -0.85),
                ("leg", 0.5, 0, -0.6),
                ("legR", 0.8, 0, -0.85),
            ]
        case .twoPoint:
            // Light crouch, both hands resting toward the knees.
            pitch = 0.3; sink = -0.07
            limbs = [
                ("arm", 0.55, 0.25, -0.7),
                ("armR", 0.55, -0.25, -0.7),
                ("leg", 0.3, 0, -0.4),
                ("legR", 0.3, 0, -0.4),
            ]
        case .split:
            // Upright split: front foot forward, back foot trailing.
            pitch = 0.12; sink = -0.02
            limbs = [
                ("arm", 0.15, 0.25, -0.35),
                ("armR", 0.15, -0.25, -0.35),
                ("leg", 0.3, 0, -0.25),
                ("legR", -0.25, 0, 0),
            ]
        case .upright:
            pitch = 0; sink = 0
            limbs = [
                ("arm", 0, 0.25, -0.15),
                ("armR", 0, -0.25, -0.15),
                ("leg", 0, 0, 0),
                ("legR", 0, 0, 0),
            ]
        }

        let pose = SCNAction.sequence([
            SCNAction.wait(duration: delay),
            SCNAction.group([
                SCNAction.rotateTo(x: pitch, y: 0, z: 0, duration: 0.25),
                SCNAction.move(to: SCNVector3(0, sink, 0), duration: 0.25),
            ]),
        ])
        figure.runAction(pose, forKey: "stance")

        for limb in limbs {
            guard let limbNode = figure.childNode(withName: limb.name, recursively: false) else { continue }
            limbNode.removeAction(forKey: "swing")
            limbNode.runAction(SCNAction.sequence([
                SCNAction.wait(duration: delay),
                SCNAction.rotateTo(x: limb.x, y: 0, z: limb.z, duration: 0.25),
            ]), forKey: "swing")
            if let joint = limbNode.childNodes.first(where: { $0.name == "shin" || $0.name == "forearm" }) {
                joint.removeAction(forKey: "bend")
                joint.runAction(SCNAction.sequence([
                    SCNAction.wait(duration: delay),
                    SCNAction.rotateTo(x: limb.joint, y: 0, z: 0, duration: 0.25),
                ]), forKey: "bend")
            }
        }
    }

    /// Which end the camera shoots from: +1 = from -Z looking toward +Z
    /// (correct for the HOME player — behind his offense when attacking and
    /// behind his defense when defending), -1 = mirrored for AWAY games so
    /// the camera always sits behind the player's own unit. Field text
    /// re-orients so it stays readable from the active side.
    private(set) var viewFacing: Float = 1

    func setViewFacing(_ facing: Float) {
        viewFacing = facing >= 0 ? 1 : -1
        orientFieldText()
        // The end wall on the camera's side would sit in front of the lens.
        rootNode.childNode(withName: "endWallPos", recursively: false)?.isHidden = viewFacing < 0
        rootNode.childNode(withName: "endWallNeg", recursively: false)?.isHidden = viewFacing > 0
        focusCamera(z: focusZ, animated: false)
    }

    /// Rotates every flat text on the field (yard numbers, end zone
    /// wordmarks, midfield logo lettering) to read correctly from the
    /// current camera side.
    private func orientFieldText() {
        let yaw: Float = viewFacing >= 0 ? .pi : 0
        for node in rootNode.childNodes
        where (node.name == "yardNumber" || node.name == "fieldDressing") && node.geometry is SCNText {
            node.eulerAngles = SCNVector3(-Float.pi / 2, yaw, 0)
        }
    }

    /// On defense the offense advances TOWARD the camera, so the offensive
    /// framing (aim point 16 yards downfield) would show mostly empty turf
    /// and pin the formation to the bottom edge. The defensive framing sits
    /// higher and steeper with the aim point on the player's own side of the
    /// ball: the snap reads in the upper third and the defensive backfield —
    /// where the play actually develops — fills the frame.
    private var defensiveFraming = false

    func setDefensiveFraming(_ defending: Bool) {
        defensiveFraming = defending
    }

    /// Pans the camera (and its look-at target) along the field so ~25 yards
    /// around the given Z stay readable at a broadcast angle.
    /// `z` is clamped to [-45, 45] so the framing never leaves the field.
    ///
    /// `pushIn` adds the pre-snap broadcast dolly: once the framing settles,
    /// the camera creeps ~2 yards toward the LOS over 2.5 s. Any new focus,
    /// kick camera, or the snap itself (`runPlay`) interrupts the dolly, and
    /// the next absolute focus move corrects the accumulated offset.
    func focusCamera(z: Float, animated: Bool = true, duration: TimeInterval = 0.8,
                     pushIn: Bool = false) {
        kickCameraActive = false
        cameraNode.removeAction(forKey: "pushIn")
        let clampedZ = max(-45, min(45, z))
        focusZ = clampedZ
        // Madden-98 framing: a LOW camera behind the player's own unit
        // looking downfield — mirrored via `viewFacing` for away games.
        // Defense swaps to the high steep variant (see defensiveFraming).
        let targetPosition = defensiveFraming
            ? SCNVector3(0, 0.5, clampedZ - viewFacing * 6)
            : SCNVector3(0, 1.5, clampedZ + viewFacing * 16)
        let cameraPosition = defensiveFraming
            ? SCNVector3(0, 30, clampedZ - viewFacing * 34)
            : SCNVector3(0, 21, clampedZ - viewFacing * 24)

        if animated {
            let targetMove = SCNAction.move(to: targetPosition, duration: duration)
            targetMove.timingMode = .easeInEaseOut
            cameraTargetNode.runAction(targetMove, forKey: "focus")

            let cameraMove = SCNAction.move(to: cameraPosition, duration: duration)
            cameraMove.timingMode = .easeInEaseOut
            cameraNode.runAction(cameraMove, forKey: "focus")
        } else {
            cameraTargetNode.removeAction(forKey: "focus")
            cameraNode.removeAction(forKey: "focus")
            cameraTargetNode.position = targetPosition
            cameraNode.position = cameraPosition
        }

        if pushIn && animated {
            // Slow dolly along the (horizontal) view direction toward the LOS.
            let dx = targetPosition.x - cameraPosition.x
            let dz = targetPosition.z - cameraPosition.z
            let length = sqrt(dx * dx + dz * dz)
            guard length > 0.1 else { return }
            let scale = 2.0 / length
            let dolly = SCNAction.moveBy(x: CGFloat(dx * scale), y: -0.4,
                                         z: CGFloat(dz * scale), duration: 2.5)
            dolly.timingMode = .easeInEaseOut
            cameraNode.runAction(SCNAction.sequence([
                SCNAction.wait(duration: duration + 0.1), dolly,
            ]), forKey: "pushIn")
        }
    }

    /// Swings the camera low behind the goalposts looking back up the field —
    /// the broadcast angle for field goals and extra points. `towardZ` is the
    /// direction the kick travels (positive = toward the +Z posts). The shot
    /// stays parked (no follow-cam) until the next `focusCamera` call.
    func kickCamera(towardZ: Float, duration: TimeInterval = 0.8) {
        kickCameraActive = true
        cameraNode.removeAction(forKey: "pushIn")
        let sign: Float = towardZ >= 0 ? 1 : -1
        let cameraPosition = SCNVector3(0, 8, sign * 72)
        let targetPosition = SCNVector3(0, 4, sign * 40)

        let targetMove = SCNAction.move(to: targetPosition, duration: duration)
        targetMove.timingMode = .easeInEaseOut
        cameraTargetNode.runAction(targetMove, forKey: "focus")

        let cameraMove = SCNAction.move(to: cameraPosition, duration: duration)
        cameraMove.timingMode = .easeInEaseOut
        cameraNode.runAction(cameraMove, forKey: "focus")
    }

    /// Runs a sequential play timeline: each step starts after the previous one
    /// finishes; within a step all moves (and the ball behavior) start together.
    /// `completion` fires on the main queue after the last step ends.
    func runPlay(steps: [PlayStep], completion: @escaping () -> Void) {
        cancelPlay()
        // The snap kills the pre-snap push-in; the follow-cam owns the shot now.
        cameraNode.removeAction(forKey: "pushIn")
        let generation = playGeneration

        var startTime: TimeInterval = 0
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime) { [weak self] in
                guard let self = self, self.playGeneration == generation else { return }
                self.execute(step: step)
            }
            startTime += effectiveDuration(of: step)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + startTime) { [weak self] in
            guard let self = self, self.playGeneration == generation else { return }
            self.detachBallToRoot()
            completion()
        }
    }

    /// Stops a running play: pending steps are dropped, running actions removed,
    /// and the ball is detached back to the root node at its current world position.
    func cancelPlay() {
        playGeneration += 1
        for node in homePlayerNodes + awayPlayerNodes {
            node.removeAction(forKey: "playMove")
            node.removeAction(forKey: "pulse")
            node.removeAction(forKey: "settleFacing")
            resetGait(of: node)
        }
        ballNode.removeAllActions()
        detachBallToRoot()
        rootNode.childNodes.filter { $0.name == "ballShadow" }.forEach { $0.removeFromParentNode() }
        rootNode.childNodes.filter { $0.name == "penaltyFlag" }.forEach { $0.removeFromParentNode() }
    }

    /// Shows or hides the football (e.g. between plays or during kick meters).
    func setBallHidden(_ hidden: Bool) {
        ballNode.isHidden = hidden
    }

    /// Briefly pulses a player node (1.2x scale up and back down) to highlight
    /// key moments — tackles, turnovers, touchdown celebrations.
    /// `nodeIndex` 0-10 = home players, 11-21 = away players.
    func pulse(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex) else { return }
        let up = SCNAction.scale(to: 1.2, duration: 0.15)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.scale(to: 1.0, duration: 0.15)
        down.timingMode = .easeInEaseOut
        node.runAction(SCNAction.sequence([up, down]), forKey: "pulse")
    }

    /// Tints the two end zones with slightly darkened team colors.
    /// End zones keep the default green until this is called.
    func setEndZoneColors(home: UIColor, away: UIColor) {
        homeEndZoneNode?.geometry?.firstMaterial?.diffuse.contents = darkenColor(home, by: 0.45)
        awayEndZoneNode?.geometry?.firstMaterial?.diffuse.contents = darkenColor(away, by: 0.45)
    }

    /// Paints team wordmarks into the end zones and a logo disc at midfield —
    /// the TV-broadcast dressing that makes the field read as THEIR stadium.
    func setFieldDressing(homeAbbr: String, awayAbbr: String, homeColor: UIColor) {
        rootNode.childNodes.filter { $0.name == "fieldDressing" }.forEach { $0.removeFromParentNode() }

        // End zone wordmarks (home at -Z, away at +Z), upright for the camera.
        for (abbr, zSign) in [(homeAbbr, Float(-1)), (awayAbbr, Float(1))] {
            let text = SCNText(string: abbr, extrusionDepth: 0.02)
            text.font = UIFont.systemFont(ofSize: 6.5, weight: .black)
            text.flatness = 0.3
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 1, alpha: 0.9)
            material.emission.contents = UIColor(white: 0.25, alpha: 1)
            text.materials = [material]

            let node = SCNNode(geometry: text)
            node.name = "fieldDressing"
            let (minB, maxB) = node.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x,
                                                   (maxB.y - minB.y) / 2 + minB.y, 0)
            node.eulerAngles = SCNVector3(-Float.pi / 2, viewFacing >= 0 ? Float.pi : 0, 0)
            node.position = SCNVector3(0, 0.03, zSign * (FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth / 2))
            rootNode.addChildNode(node)
        }

        // Midfield logo disc + abbreviation — painted into the turf, not a
        // glowing sticker, so it reads like the reference broadcast look.
        let disc = SCNCylinder(radius: 5.2, height: 0.02)
        let discMaterial = SCNMaterial()
        discMaterial.diffuse.contents = darkenColor(homeColor, by: 0.18).withAlphaComponent(0.55)
        discMaterial.roughness.contents = 0.95
        disc.materials = [discMaterial]
        let discNode = SCNNode(geometry: disc)
        discNode.name = "fieldDressing"
        discNode.position = SCNVector3(0, 0.015, 0)
        rootNode.addChildNode(discNode)

        let logo = SCNText(string: homeAbbr, extrusionDepth: 0.02)
        logo.font = UIFont.systemFont(ofSize: 3.6, weight: .black)
        logo.flatness = 0.3
        let logoMaterial = SCNMaterial()
        logoMaterial.diffuse.contents = UIColor(white: 1, alpha: 0.95)
        logo.materials = [logoMaterial]
        let logoNode = SCNNode(geometry: logo)
        logoNode.name = "fieldDressing"
        let (minL, maxL) = logoNode.boundingBox
        logoNode.pivot = SCNMatrix4MakeTranslation((maxL.x - minL.x) / 2 + minL.x,
                                                   (maxL.y - minL.y) / 2 + minL.y, 0)
        logoNode.eulerAngles = SCNVector3(-Float.pi / 2, viewFacing >= 0 ? Float.pi : 0, 0)
        logoNode.position = SCNVector3(0, 0.035, 0)
        rootNode.addChildNode(logoNode)
    }

    /// Penalty flag: a small yellow cloth arcs in from the near sideline,
    /// tumbling end over end, lands on the turf around the given Z and fades
    /// out after a beat. Purely presentational — call it when a play resolves
    /// with a `.penalty` outcome.
    func throwFlag(atZ z: Float) {
        let clampedZ = max(-50, min(50, z))

        let geometry = SCNBox(width: 0.5, height: 0.14, length: 0.5, chamferRadius: 0.04)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 1.0, green: 0.84, blue: 0.1, alpha: 1)
        material.emission.contents = UIColor(red: 0.45, green: 0.36, blue: 0.03, alpha: 1)
        geometry.materials = [material]
        let flag = SCNNode(geometry: geometry)
        flag.name = "penaltyFlag"

        // Thrown from the officials' side, chest height, a few yards behind
        // the spot — like a back judge reaching for his pocket.
        let start = SCNVector3(-FieldConstants.fieldWidth / 2 - 1.5, 1.4, clampedZ - 5)
        let target = SCNVector3(Float.random(in: -5...3), 0.1, clampedZ + Float.random(in: -1.5...1.5))
        flag.position = start
        rootNode.addChildNode(flag)

        let flight: TimeInterval = 0.8
        let apex: Float = 5
        let arc = SCNAction.customAction(duration: flight) { node, elapsed in
            let t = max(0, min(Float(elapsed) / Float(flight), 1))
            node.position = SCNVector3(
                start.x + (target.x - start.x) * t,
                start.y + (target.y - start.y) * t + apex * 4 * t * (1 - t),
                start.z + (target.z - start.z) * t
            )
        }
        let tumble = SCNAction.rotateBy(x: CGFloat.pi * 3, y: CGFloat.pi * 2, z: 0, duration: flight)
        flag.runAction(SCNAction.group([arc, tumble]))
        flag.runAction(SCNAction.sequence([
            SCNAction.wait(duration: flight + 2.0),
            SCNAction.fadeOut(duration: 0.4),
            SCNAction.removeFromParentNode(),
        ]))
    }

    /// Gold-and-white confetti burst over the end zone for touchdowns.
    func celebrate(atZ z: Float) {
        let colors: [UIColor] = [
            UIColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1),
            UIColor(white: 0.95, alpha: 1),
            homeColor, awayColor,
        ]
        var seed = UInt64(truncatingIfNeeded: abs(Int(z * 97)) + 13)
        func nextRandom() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFF) / Float(0xFFFF)
        }
        for i in 0..<42 {
            let geometry = SCNBox(width: 0.22, height: 0.05, length: 0.14, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = colors[i % colors.count]
            material.lightingModel = .constant
            geometry.materials = [material]
            let piece = SCNNode(geometry: geometry)
            piece.position = SCNVector3((nextRandom() - 0.5) * 24, 0.5, z + (nextRandom() - 0.5) * 10)
            rootNode.addChildNode(piece)

            let upTime = 0.35 + Double(nextRandom()) * 0.3
            let rise = SCNAction.moveBy(x: CGFloat((nextRandom() - 0.5) * 4),
                                        y: CGFloat(3.5 + nextRandom() * 3),
                                        z: CGFloat((nextRandom() - 0.5) * 4), duration: upTime)
            rise.timingMode = .easeOut
            let drop = SCNAction.moveBy(x: CGFloat((nextRandom() - 0.5) * 3),
                                        y: CGFloat(-4 - nextRandom() * 2.5),
                                        z: CGFloat((nextRandom() - 0.5) * 3), duration: 1.0 + Double(nextRandom()) * 0.5)
            drop.timingMode = .easeIn
            let tumble = SCNAction.repeatForever(SCNAction.rotateBy(
                x: CGFloat(nextRandom() * 8 - 4), y: CGFloat(nextRandom() * 8 - 4), z: 0, duration: 0.6))
            piece.runAction(tumble)
            piece.runAction(SCNAction.sequence([
                rise, drop, SCNAction.fadeOut(duration: 0.3), SCNAction.removeFromParentNode(),
            ]))
        }
    }

    /// Moves the broadcast line-of-scrimmage (blue) and first-down (yellow)
    /// markers. Pass nil to hide either.
    func updateMarkers(losZ: Float?, firstDownZ: Float?) {
        if let losZ {
            losMarkerNode.isHidden = false
            losMarkerNode.position = SCNVector3(0, 0.012, max(-50, min(50, losZ)))
        } else {
            losMarkerNode.isHidden = true
        }
        if let firstDownZ {
            firstDownMarkerNode.isHidden = false
            firstDownMarkerNode.position = SCNVector3(0, 0.012, max(-50, min(50, firstDownZ)))
        } else {
            firstDownMarkerNode.isHidden = true
        }
    }

    // MARK: - Play Execution (private)

    private func playerNode(at index: Int) -> SCNNode? {
        let allPlayers = homePlayerNodes + awayPlayerNodes
        guard index >= 0, index < allPlayers.count else { return nil }
        return allPlayers[index]
    }

    /// One full leg cycle for a runner at `speed` yards/second — faster feet
    /// as the player moves faster; backpedals chop at a fixed cadence.
    private func strideTime(forSpeed speed: Float, backpedal: Bool) -> TimeInterval {
        backpedal ? 0.3 : min(max(0.38 - TimeInterval(speed) * 0.022, 0.16), 0.34)
    }

    /// Moves a player container to `target` with the full running presentation:
    /// the figure turns toward its direction of travel, leans forward (harder
    /// the faster he runs) and bobs while moving, then straightens up on
    /// arrival. Sharp direction changes bank the figure into the turn for a
    /// beat. `backpedal` keeps the node facing where it faces (QB dropback):
    /// no turn, a slight backward lean and a choppier, smaller gait.
    /// Tiny shuffles (sub-0.4yd) skip the gait so linemen don't sprint
    /// through half-yard adjustments.
    private func run(node: SCNNode, to target: SCNVector3, duration: TimeInterval, key: String,
                     backpedal: Bool = false) {
        let move = SCNAction.move(to: target, duration: duration)
        // Play steps chain into each other, so easing in and out of EVERY
        // step makes players pump-stop at each boundary. Linear keeps the
        // velocity continuous across steps; only formation moves ease.
        move.timingMode = key == "playMove" ? .linear : .easeInEaseOut
        node.runAction(move, forKey: key)

        let dx = target.x - node.position.x
        let dz = target.z - node.position.z
        let distance = sqrt(dx * dx + dz * dz)
        guard distance > 0.4, duration > 0.15 else { return }

        // Turn size BEFORE the facing action rewrites the yaw — successive
        // move steps in different directions read as a cut, which banks the
        // body into the turn below.
        let yaw = atan2(dx, dz)
        var turn = yaw - node.eulerAngles.y
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }

        if backpedal {
            node.removeAction(forKey: "facing")  // hold the downfield facing
        } else {
            let face = SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.18, usesShortestUnitArc: true)
            face.timingMode = .easeInEaseOut
            node.runAction(face, forKey: "facing")
        }

        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "stance")  // the snap breaks the pre-snap pose

        let speed = distance / Float(duration)
        let stride = strideTime(forSpeed: speed, backpedal: backpedal)

        // Bob synced to the leg cycle.
        let bobUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: stride / 2)
        bobUp.timingMode = .easeInEaseOut
        let cycles = max(Int(duration / stride), 1)
        let bob = SCNAction.repeat(SCNAction.sequence([bobUp, bobUp.reversed()]), count: cycles)
        // Rise out of any stance sink first so the bob oscillates around zero.
        let rise = SCNAction.move(to: SCNVector3Zero, duration: 0.1)

        // Forward lean scales with speed (~8-12°); backpedal sits slightly back.
        let lean: CGFloat = backpedal ? -0.1 : CGFloat(0.14 + min(speed, 9) / 9 * 0.08)
        // Momentary inward bank on a sharp cut, released mid-move.
        let bank: CGFloat = (!backpedal && key == "playMove" && abs(turn) > 0.6)
            ? CGFloat(max(-0.32, min(0.32, -turn * 0.35)))
            : 0
        let leanIn = SCNAction.rotateTo(x: lean, y: 0, z: bank, duration: 0.15)
        leanIn.timingMode = .easeOut
        let leanPhase: SCNAction
        if bank == 0 {
            leanPhase = leanIn
        } else {
            let release = SCNAction.rotateTo(x: lean, y: 0, z: 0, duration: 0.3)
            release.timingMode = .easeInEaseOut
            leanPhase = SCNAction.sequence([leanIn, release])
        }

        let straighten = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2),
            SCNAction.move(to: SCNVector3Zero, duration: 0.2),
        ])
        figure.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.sequence([rise, bob]), leanPhase]),
            straighten,
        ]), forKey: "gait")

        // Run cycle: legs scissor around the hip, arms pump opposite — the
        // single biggest "he's actually running" cue at this camera distance.
        swingLimbs(of: figure, duration: duration,
                   carrying: playerNode(at: carryingIndex ?? -1) === node,
                   speed: speed, backpedal: backpedal)
    }

    /// Alternating limb swings for the duration of a move, ending neutral.
    /// Knees and elbows bend while running; the ball-carrier's left arm stays
    /// tucked around the ball instead of pumping. Cadence and amplitude scale
    /// with `speed` (yards/s), and the torso counter-rotates lightly against
    /// the legs. Backpedals chop with short, small steps.
    private func swingLimbs(of figure: SCNNode, duration: TimeInterval, carrying: Bool = false,
                            speed: Float = 5, backpedal: Bool = false) {
        let stride = strideTime(forSpeed: speed, backpedal: backpedal)
        let cycles = max(Int(duration / stride), 1)
        let swing: Float = backpedal ? 0.4 : min(0.45 + speed * 0.035, 0.8)

        func swingAction(startForward: Bool, restZ: CGFloat) -> SCNAction {
            let fwd = SCNAction.rotateTo(x: CGFloat(-swing), y: 0, z: restZ, duration: stride / 2)
            fwd.timingMode = .easeInEaseOut
            let back = SCNAction.rotateTo(x: CGFloat(swing), y: 0, z: restZ, duration: stride / 2)
            back.timingMode = .easeInEaseOut
            let cycle = startForward ? SCNAction.sequence([fwd, back]) : SCNAction.sequence([back, fwd])
            let neutral = SCNAction.rotateTo(x: 0, y: 0, z: restZ, duration: 0.15)
            return SCNAction.sequence([SCNAction.repeat(cycle, count: cycles), neutral])
        }

        // Light upper-body counter-rotation against the leg cycle — the
        // shoulders working with the arm pump.
        if let body = figure.childNode(withName: "body", recursively: false) {
            body.removeAction(forKey: "twist")
            let amplitude: CGFloat = backpedal ? 0.05 : 0.1
            let left = SCNAction.rotateTo(x: 0, y: amplitude, z: 0, duration: stride / 2)
            left.timingMode = .easeInEaseOut
            let right = SCNAction.rotateTo(x: 0, y: -amplitude, z: 0, duration: stride / 2)
            right.timingMode = .easeInEaseOut
            let neutral = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15)
            body.runAction(SCNAction.sequence([
                SCNAction.repeat(SCNAction.sequence([left, right]), count: cycles), neutral,
            ]), forKey: "twist")
        }

        /// Bend a joint (knee/elbow) for the run, release to rest afterwards.
        func bendAction(bend: CGFloat, rest: CGFloat) -> SCNAction {
            SCNAction.sequence([
                SCNAction.rotateTo(x: bend, y: 0, z: 0, duration: 0.15),
                SCNAction.wait(duration: max(duration - 0.15, 0)),
                SCNAction.rotateTo(x: rest, y: 0, z: 0, duration: 0.15),
            ])
        }

        let limbs: [(name: String, forward: Bool, restZ: CGFloat, joint: String, bend: CGFloat, jointRest: CGFloat)] = [
            ("leg", true, 0, "shin", 0.55, 0),
            ("legR", false, 0, "shin", 0.55, 0),
            ("arm", false, 0.25, "forearm", -1.0, -0.15),
            ("armR", true, -0.25, "forearm", -1.0, -0.15),
        ]
        for limb in limbs {
            guard let node = figure.childNode(withName: limb.name, recursively: false) else { continue }
            node.removeAction(forKey: "swing")
            let joint = node.childNode(withName: limb.joint, recursively: false)
            joint?.removeAction(forKey: "bend")

            if carrying && limb.name == "arm" {
                // Ball arm: tucked tight, no pumping.
                node.runAction(SCNAction.rotateTo(x: -0.55, y: 0, z: 0.35, duration: 0.2), forKey: "swing")
                joint?.runAction(SCNAction.rotateTo(x: -1.35, y: 0, z: 0, duration: 0.2), forKey: "bend")
                continue
            }
            node.runAction(swingAction(startForward: limb.forward, restZ: limb.restZ), forKey: "swing")
            joint?.runAction(bendAction(bend: limb.bend, rest: limb.jointRest), forKey: "bend")
        }
    }

    /// Both arms shoot up for a beat — catch attempts and pick attempts —
    /// with a small leap at the ball while the arms are up.
    private func reach(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "hop")
        let hopUp = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: 0.22)
        hopUp.timingMode = .easeOut
        let hopDown = SCNAction.moveBy(x: 0, y: -0.25, z: 0, duration: 0.24)
        hopDown.timingMode = .easeIn
        figure.runAction(SCNAction.sequence([hopUp, hopDown]), forKey: "hop")
        for name in ["arm", "armR"] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            let up = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 2.7 : -2.7, duration: 0.25)
            up.timingMode = .easeOut
            let down = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.3)
            arm.runAction(SCNAction.sequence([up, SCNAction.wait(duration: 0.5), down]), forKey: "swing")
        }
    }

    /// The carrier and tackler hit the turf, lie there a beat, and get up.
    /// `getUpDelay` staggers the rise for gang-tackle piles — the last man
    /// on (top of the pile) climbs off first. With `stayDown` the figure
    /// collapses and stays on the turf (injury presentation) — the next
    /// formation move stands him back up, by which point the node already
    /// wears the replacement's number.
    private func fall(nodeIndex: Int, delay: TimeInterval = 0, stayDown: Bool = false,
                      getUpDelay: TimeInterval = 0) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "stance")
        let variance = Float(nodeIndex % 3 - 1) * 0.3
        let down = SCNAction.group([
            SCNAction.rotateTo(x: CGFloat(-1.45 + variance * 0.1), y: CGFloat(variance), z: 0, duration: 0.3),
            SCNAction.move(to: SCNVector3(0, -0.32, 0.15), duration: 0.3),
        ])
        down.timingMode = .easeIn
        if stayDown {
            figure.runAction(SCNAction.sequence([
                SCNAction.wait(duration: delay), down,
            ]), forKey: "fall")
            return
        }
        let up = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.45),
            SCNAction.move(to: SCNVector3Zero, duration: 0.45),
        ])
        up.timingMode = .easeInEaseOut
        figure.runAction(SCNAction.sequence([
            SCNAction.wait(duration: delay), down,
            SCNAction.wait(duration: 0.8 + getUpDelay), up,
        ]), forKey: "fall")
    }

    /// Touchdown celebration: the scorer leaps with both arms thrown up.
    /// The choreography spikes the ball right after via a short ball arc.
    private func celebrationJump(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "hop")
        let up = SCNAction.moveBy(x: 0, y: 0.85, z: 0, duration: 0.3)
        up.timingMode = .easeOut
        let down = SCNAction.moveBy(x: 0, y: -0.85, z: 0, duration: 0.32)
        down.timingMode = .easeIn
        let settle = SCNAction.move(to: SCNVector3Zero, duration: 0.1)
        figure.runAction(SCNAction.sequence([up, down, settle]), forKey: "hop")
        for name in ["arm", "armR"] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            let raise = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 2.6 : -2.6, duration: 0.25)
            raise.timingMode = .easeOut
            let lower = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.3)
            arm.runAction(SCNAction.sequence([raise, SCNAction.wait(duration: 0.7), lower]), forKey: "swing")
        }
    }

    /// Injury presentation: the player drops and stays on the turf until the
    /// next formation move. `nodeIndex` 0-10 = home players, 11-21 = away.
    func stayDown(nodeIndex: Int) {
        fall(nodeIndex: nodeIndex, stayDown: true)
    }

    /// Snaps a figure out of its running pose (used when a play is cancelled).
    private func resetGait(of node: SCNNode) {
        node.removeAction(forKey: "facing")
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "stance")
        figure.removeAction(forKey: "fall")
        figure.removeAction(forKey: "hop")
        figure.position = SCNVector3Zero
        figure.eulerAngles = SCNVector3Zero
        if let body = figure.childNode(withName: "body", recursively: false) {
            body.removeAction(forKey: "twist")
            body.eulerAngles = SCNVector3Zero
        }
        for name in ["leg", "legR", "arm", "armR"] {
            guard let limb = figure.childNode(withName: name, recursively: false) else { continue }
            limb.removeAction(forKey: "swing")
            limb.eulerAngles = SCNVector3(0, 0, limb.eulerAngles.z)
            limb.eulerAngles.x = 0
            if let joint = limb.childNodes.first(where: { $0.name == "shin" || $0.name == "forearm" }) {
                joint.removeAction(forKey: "bend")
                joint.eulerAngles.x = joint.name == "forearm" ? -0.15 : 0
            }
        }
    }

    /// A step lasts at least `duration`, stretched by its longest move or ball flight.
    private func effectiveDuration(of step: PlayStep) -> TimeInterval {
        var duration = step.duration
        for move in step.moves {
            duration = max(duration, move.duration)
        }
        switch step.ballMove {
        case .arc(_, _, let ballDuration), .slide(_, let ballDuration):
            duration = max(duration, ballDuration)
        default:
            break
        }
        return duration
    }

    /// Kicks off everything inside a single step: player moves, pulses, falls,
    /// reaches, celebrations, ball behavior — plus the follow-cam on long carries.
    private func execute(step: PlayStep) {
        for move in step.moves {
            guard let node = playerNode(at: move.nodeIndex) else { continue }
            run(node: node, to: move.to, duration: move.duration, key: "playMove",
                backpedal: step.backpedals.contains(move.nodeIndex))
        }

        for index in step.pulses { pulse(nodeIndex: index) }
        for index in step.reaches { reach(nodeIndex: index) }
        for index in step.celebrates { celebrationJump(nodeIndex: index) }
        // Falls stagger DOWN in list order; the pile unstacks in reverse —
        // the last man on (top of the pile) is the first back on his feet.
        for (offset, index) in step.falls.enumerated() {
            fall(nodeIndex: index, delay: Double(offset) * 0.12,
                 getUpDelay: Double(max(step.falls.count - 1 - offset, 0)) * 0.22)
        }

        switch step.ballMove {
        case .carry(let nodeIndex):
            attachBall(toPlayerIndex: nodeIndex)
            // Follow-cam: when the carrier breaks well past the current frame,
            // pan downfield with him so long gains don't run out of shot.
            if !kickCameraActive,
               let move = step.moves.first(where: { $0.nodeIndex == nodeIndex }),
               abs(move.to.z - focusZ) > 11 {
                followCamera(toZ: move.to.z, stepDuration: move.duration)
            }
        case .arc(let to, let apex, let duration):
            runBallArc(to: to, apex: apex, duration: duration)
            if !kickCameraActive, abs(to.z - focusZ) > 11 {
                followCamera(toZ: to.z, stepDuration: duration)
            }
        case .slide(let to, let duration):
            runBallSlide(to: to, duration: duration)
        case nil:
            break
        }
    }

    /// Follow-cam pan with softened timing: short hops get proportionally
    /// longer, eased moves so successive refocuses blend instead of jerking;
    /// only genuinely long breaks pan at full speed.
    private func followCamera(toZ z: Float, stepDuration: TimeInterval) {
        let pan = abs(z - focusZ)
        let duration = max(stepDuration, min(1.7, 0.7 + TimeInterval(pan) * 0.03))
        focusCamera(z: z, animated: true, duration: duration)
    }

    /// Parents the ball to a player so it rides along with every move (carry).
    private func attachBall(toPlayerIndex index: Int) {
        guard let node = playerNode(at: index), ballNode.parent !== node else { return }
        carryingIndex = index
        ballNode.removeAllActions()
        ballNode.eulerAngles = SCNVector3Zero
        ballNode.removeFromParentNode()
        node.addChildNode(ballNode)
        // Tucked under the left arm rather than floating at the chest.
        ballNode.position = SCNVector3(-0.32, 0.28, 0.18)

        // Carry pose right away (swingLimbs keeps it during moves).
        if let figure = node.childNode(withName: "figure", recursively: false),
           let arm = figure.childNode(withName: "arm", recursively: false) {
            arm.removeAction(forKey: "swing")
            arm.runAction(SCNAction.rotateTo(x: -0.55, y: 0, z: 0.35, duration: 0.2), forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: -1.35, y: 0, z: 0, duration: 0.2), forKey: "bend")
        }
    }

    /// Re-parents the ball to the root node, preserving its world position.
    private func detachBallToRoot() {
        if let previous = playerNode(at: carryingIndex ?? -1),
           let figure = previous.childNode(withName: "figure", recursively: false),
           let arm = figure.childNode(withName: "arm", recursively: false) {
            arm.runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0.25, duration: 0.2), forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.2), forKey: "bend")
        }
        carryingIndex = nil
        guard ballNode.parent !== rootNode else { return }
        let worldPosition = ballNode.worldPosition
        ballNode.removeFromParentNode()
        rootNode.addChildNode(ballNode)
        ballNode.position = worldPosition
    }

    /// Flies the ball along a parabola from its current position to `target`.
    private func runBallArc(to target: SCNVector3, apex: Float, duration: TimeInterval) {
        // Whoever carried the ball into this flight is the passer — capture
        // him before the detach clears the carry, then whip his arm through.
        let thrower = playerNode(at: carryingIndex ?? -1)
        detachBallToRoot()
        ballNode.removeAllActions()
        guard duration > 0 else {
            ballNode.position = target
            return
        }
        if let thrower { throwMotion(of: thrower) }

        let start = ballNode.position
        let arc = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = max(0, min(Float(elapsed) / Float(duration), 1))
            node.position = SCNVector3(
                start.x + (target.x - start.x) * t,
                start.y + (target.y - start.y) * t + apex * 4 * t * (1 - t),
                start.z + (target.z - start.z) * t
            )
        }
        // Snap exactly onto the target in case the last frame lands short.
        let settle = SCNAction.move(to: target, duration: 0)
        ballNode.runAction(SCNAction.sequence([arc, settle]), forKey: "ballMove")

        // Passes spiral around the long axis; kicks/punts (high apex) tumble
        // end over end. Reset the orientation when the flight lands.
        let spin: SCNAction = apex >= 8
            ? SCNAction.repeatForever(SCNAction.rotateBy(x: -2 * .pi, y: 0, z: 0, duration: 0.7))
            : SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 0, z: 2 * .pi, duration: 0.35))
        ballNode.runAction(spin, forKey: "ballSpin")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.ballNode.removeAction(forKey: "ballSpin")
            self?.ballNode.eulerAngles = SCNVector3Zero
        }

        // Flight shadow: a small dark blob slides along the turf under the
        // ball (same lerp, no y/apex term) and vanishes when the flight ends —
        // the ground reference that sells the height of the arc.
        let shadowGeometry = SCNCylinder(radius: 0.35, height: 0.01)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = UIColor(white: 0, alpha: 0.3)
        shadowMaterial.lightingModel = .constant
        shadowGeometry.materials = [shadowMaterial]
        let shadow = SCNNode(geometry: shadowGeometry)
        shadow.name = "ballShadow"
        shadow.castsShadow = false
        shadow.position = SCNVector3(start.x, 0.025, start.z)
        rootNode.addChildNode(shadow)
        let track = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = max(0, min(Float(elapsed) / Float(duration), 1))
            node.position = SCNVector3(
                start.x + (target.x - start.x) * t,
                0.025,
                start.z + (target.z - start.z) * t
            )
        }
        shadow.runAction(SCNAction.sequence([track, SCNAction.removeFromParentNode()]))
    }

    /// The passer's right arm cocks back and snaps forward overhead as the
    /// ball releases into its arc, then settles back to neutral.
    private func throwMotion(of node: SCNNode) {
        guard let figure = node.childNode(withName: "figure", recursively: false),
              let arm = figure.childNode(withName: "armR", recursively: false) else { return }
        arm.removeAction(forKey: "swing")
        let windup = SCNAction.rotateTo(x: 2.2, y: 0, z: -0.25, duration: 0.16)
        windup.timingMode = .easeOut
        let release = SCNAction.rotateTo(x: -2.6, y: 0, z: -0.25, duration: 0.18)
        release.timingMode = .easeIn
        let neutral = SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.3)
        neutral.timingMode = .easeInEaseOut
        arm.runAction(SCNAction.sequence([windup, release, SCNAction.wait(duration: 0.2), neutral]),
                      forKey: "swing")
    }

    /// Slides the ball flat along the ground (snaps, rolling punts, dead balls).
    private func runBallSlide(to target: SCNVector3, duration: TimeInterval) {
        detachBallToRoot()
        ballNode.removeAllActions()
        let action = SCNAction.move(to: target, duration: duration)
        action.timingMode = .easeOut
        ballNode.runAction(action, forKey: "ballMove")
    }

    /// Rewrites the floating jersey number on an existing player node.
    private func updateJerseyNumber(on node: SCNNode, to number: Int) {
        guard let numberNode = node.childNode(withName: "number", recursively: false),
              let text = numberNode.geometry as? SCNText,
              (text.string as? String) != "\(number)" else { return }
        text.string = "\(number)"

        // Re-center the pivot for the new digit width
        let (minB, maxB) = numberNode.boundingBox
        numberNode.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        node.name = "player_\(number)"
    }

    // MARK: - Field Construction

    /// A tiling speckled-turf texture — dark greens with per-pixel noise, the
    /// gritty Madden-98 grass instead of a flat fill.
    private static func turfTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        var seed: UInt64 = 0x75F1
        func nextRandom() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
        }
        let tones: [UIColor] = [
            UIColor(red: 0.10, green: 0.30, blue: 0.11, alpha: 1),
            UIColor(red: 0.12, green: 0.35, blue: 0.13, alpha: 1),
            UIColor(red: 0.09, green: 0.26, blue: 0.10, alpha: 1),
            UIColor(red: 0.14, green: 0.38, blue: 0.14, alpha: 1),
        ]
        return renderer.image { ctx in
            tones[0].setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<2600 {
                tones[Int(nextRandom() * CGFloat(tones.count - 1))].setFill()
                ctx.fill(CGRect(x: nextRandom() * 126, y: nextRandom() * 126,
                                width: 1.6 + nextRandom(), height: 1.6 + nextRandom()))
            }
        }
    }

    private func buildFieldSurface() {
        // Main playing field
        let fieldGeometry = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth),
            height: CGFloat(FieldConstants.fieldThickness),
            length: CGFloat(FieldConstants.fieldLength),
            chamferRadius: 0
        )
        let grassMaterial = SCNMaterial()
        grassMaterial.diffuse.contents = Self.turfTexture()
        grassMaterial.diffuse.wrapS = .repeat
        grassMaterial.diffuse.wrapT = .repeat
        grassMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 12, 1)
        grassMaterial.roughness.contents = 0.95
        fieldGeometry.materials = [grassMaterial]

        let fieldNode = SCNNode(geometry: fieldGeometry)
        fieldNode.position = SCNVector3(0, -FieldConstants.fieldThickness / 2, 0)
        rootNode.addChildNode(fieldNode)

        // Darker border/surroundings
        let surroundGeometry = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth + 12),
            height: CGFloat(FieldConstants.fieldThickness),
            length: CGFloat(FieldConstants.totalLength + 12),
            chamferRadius: 0
        )
        let borderMaterial = SCNMaterial()
        borderMaterial.diffuse.contents = FieldColors.fieldBorder
        surroundGeometry.materials = [borderMaterial]

        let surroundNode = SCNNode(geometry: surroundGeometry)
        surroundNode.position = SCNVector3(0, -FieldConstants.fieldThickness / 2 - 0.01, 0)
        rootNode.addChildNode(surroundNode)
    }

    /// Alternating light/dark mowing stripes every 5 yards — the classic
    /// broadcast/Madden look. Thin overlays just above the base grass and
    /// below the painted lines.
    private func buildMowingStripes() {
        let lightStripe = SCNMaterial()
        lightStripe.diffuse.contents = UIColor(red: 0.15, green: 0.42, blue: 0.15, alpha: 0.45)
        lightStripe.transparency = 0.45
        lightStripe.roughness.contents = 0.9

        for (index, yard) in stride(from: 0, to: 100, by: 5).enumerated() {
            guard index % 2 == 0 else { continue }  // every other 5-yard band
            let stripeGeometry = SCNBox(
                width: CGFloat(FieldConstants.fieldWidth),
                height: 0.01,
                length: 5,
                chamferRadius: 0
            )
            stripeGeometry.materials = [lightStripe]
            let stripe = SCNNode(geometry: stripeGeometry)
            stripe.position = SCNVector3(0, 0.005, Float(yard) - FieldConstants.fieldLength / 2 + 2.5)
            rootNode.addChildNode(stripe)
        }
    }

    /// A small tiling texture of colored specks on dark rows — reads as a
    /// crowd from the game camera without any assets.
    private static func crowdTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        var seed: UInt64 = 0x5EED
        func nextRandom() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFF) / CGFloat(0xFFFF)
        }
        let palette: [UIColor] = [
            UIColor(red: 0.75, green: 0.72, blue: 0.65, alpha: 1),
            UIColor(red: 0.55, green: 0.30, blue: 0.25, alpha: 1),
            UIColor(red: 0.30, green: 0.40, blue: 0.60, alpha: 1),
            UIColor(red: 0.80, green: 0.65, blue: 0.30, alpha: 1),
            UIColor(red: 0.35, green: 0.55, blue: 0.40, alpha: 1),
            UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1),
        ]
        return renderer.image { ctx in
            UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for row in stride(from: 2, to: 128, by: 6) {
                for col in stride(from: 1, to: 128, by: 4) {
                    guard nextRandom() > 0.25 else { continue }
                    palette[Int(nextRandom() * CGFloat(palette.count - 1))].setFill()
                    ctx.fill(CGRect(x: CGFloat(col), y: CGFloat(row),
                                    width: 2.4, height: 2.4))
                }
            }
        }
    }

    private func buildEndZones() {
        // Home end zone (negative Z). Each end zone gets its own geometry +
        // material so setEndZoneColors(home:away:) can tint them independently.
        let homeEndZone = makeEndZoneNode()
        homeEndZone.position = SCNVector3(
            0,
            -FieldConstants.fieldThickness / 2 + 0.01,
            -(FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth / 2)
        )
        rootNode.addChildNode(homeEndZone)
        homeEndZoneNode = homeEndZone

        // Away end zone (positive Z)
        let awayEndZone = makeEndZoneNode()
        awayEndZone.position = SCNVector3(
            0,
            -FieldConstants.fieldThickness / 2 + 0.01,
            FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth / 2
        )
        rootNode.addChildNode(awayEndZone)
        awayEndZoneNode = awayEndZone

        // End zone back lines
        for zSign: Float in [-1, 1] {
            let lineZ = zSign * (FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth)
            addYardLine(atZ: lineZ, thickness: 0.15)
        }
    }

    private func makeEndZoneNode() -> SCNNode {
        let endZoneGeometry = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth),
            height: CGFloat(FieldConstants.fieldThickness),
            length: CGFloat(FieldConstants.endZoneDepth),
            chamferRadius: 0
        )
        let endZoneMaterial = SCNMaterial()
        endZoneMaterial.diffuse.contents = FieldColors.endZone
        endZoneMaterial.roughness.contents = 0.9
        endZoneGeometry.materials = [endZoneMaterial]
        return SCNNode(geometry: endZoneGeometry)
    }

    private func buildYardLines() {
        let halfField = FieldConstants.fieldLength / 2  // 50

        // Goal lines (thicker)
        addYardLine(atZ: -halfField, thickness: 0.2)
        addYardLine(atZ: halfField, thickness: 0.2)

        // Every 5 yards
        for yard in stride(from: 5, through: 95, by: 5) {
            let z = Float(yard) - halfField
            let thickness: Float = (yard == 50) ? 0.2 : 0.1
            addYardLine(atZ: z, thickness: thickness)
        }

        // Single-yard lines (shorter tick marks at each sideline)
        for yard in 1...99 {
            if yard % 5 == 0 { continue }
            let z = Float(yard) - halfField
            addSidelineTick(atZ: z)
        }
    }

    private func addYardLine(atZ z: Float, thickness: Float) {
        let lineGeometry = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth),
            height: 0.02,
            length: CGFloat(thickness),
            chamferRadius: 0
        )
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = FieldColors.yardLine
        lineMaterial.emission.contents = UIColor(white: 0.3, alpha: 1.0)
        lineGeometry.materials = [lineMaterial]

        let lineNode = SCNNode(geometry: lineGeometry)
        lineNode.position = SCNVector3(0, 0.01, z)
        rootNode.addChildNode(lineNode)
    }

    private func addSidelineTick(atZ z: Float) {
        let tickGeometry = SCNBox(
            width: 0.6,
            height: 0.02,
            length: 0.08,
            chamferRadius: 0
        )
        let tickMaterial = SCNMaterial()
        tickMaterial.diffuse.contents = FieldColors.yardLine
        tickGeometry.materials = [tickMaterial]

        let halfWidth = FieldConstants.fieldWidth / 2

        // Left sideline tick
        let leftTick = SCNNode(geometry: tickGeometry)
        leftTick.position = SCNVector3(-halfWidth + 0.3, 0.01, z)
        rootNode.addChildNode(leftTick)

        // Right sideline tick
        let rightTick = SCNNode(geometry: tickGeometry)
        rightTick.position = SCNVector3(halfWidth - 0.3, 0.01, z)
        rootNode.addChildNode(rightTick)
    }

    private func buildHashMarks() {
        let halfWidth = FieldConstants.fieldWidth / 2
        let leftHash = -halfWidth + FieldConstants.hashInset
        let rightHash = halfWidth - FieldConstants.hashInset

        for yard in 1...99 {
            let z = Float(yard) - FieldConstants.fieldLength / 2

            // Skip every 5-yard line (those are full-width already)
            if yard % 5 == 0 { continue }

            let hashGeometry = SCNBox(
                width: CGFloat(FieldConstants.hashMarkWidth),
                height: 0.02,
                length: CGFloat(FieldConstants.hashMarkLength),
                chamferRadius: 0
            )
            let hashMaterial = SCNMaterial()
            hashMaterial.diffuse.contents = FieldColors.yardLine
            hashGeometry.materials = [hashMaterial]

            let leftNode = SCNNode(geometry: hashGeometry)
            leftNode.position = SCNVector3(leftHash, 0.01, z)
            rootNode.addChildNode(leftNode)

            let rightNode = SCNNode(geometry: hashGeometry.copy() as! SCNBox)
            rightNode.geometry?.materials = [hashMaterial]
            rightNode.position = SCNVector3(rightHash, 0.01, z)
            rootNode.addChildNode(rightNode)
        }
    }

    private func buildNumbers() {
        let halfField = FieldConstants.fieldLength / 2
        // Yard numbers: displayed at 10, 20, 30, 40, 50 from each goal line
        // Labels shown: 10, 20, 30, 40, 50, 40, 30, 20, 10
        let yardMarks: [(yard: Int, label: String)] = [
            (10, "1 0"), (20, "2 0"), (30, "3 0"), (40, "4 0"), (50, "5 0"),
            (60, "4 0"), (70, "3 0"), (80, "2 0"), (90, "1 0")
        ]

        let halfWidth = FieldConstants.fieldWidth / 2

        for mark in yardMarks {
            let z = Float(mark.yard) - halfField

            // Left side numbers
            addFieldNumber(mark.label, atX: -halfWidth + 7, z: z, facingLeft: true)
            // Right side numbers
            addFieldNumber(mark.label, atX: halfWidth - 7, z: z, facingLeft: false)
        }
    }

    private func addFieldNumber(_ text: String, atX x: Float, z: Float, facingLeft: Bool) {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.02)
        textGeometry.font = UIFont.systemFont(ofSize: 2.5, weight: .bold)
        textGeometry.flatness = 0.3

        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = FieldColors.numbers
        textMaterial.emission.contents = UIColor(white: 0.15, alpha: 1.0)
        textGeometry.materials = [textMaterial]

        let textNode = SCNNode(geometry: textGeometry)

        // Center the text geometry
        let (minBound, maxBound) = textNode.boundingBox
        let textWidth = maxBound.x - minBound.x
        let textHeight = maxBound.y - minBound.y

        textNode.pivot = SCNMatrix4MakeTranslation(
            textWidth / 2 + minBound.x,
            textHeight / 2 + minBound.y,
            0
        )

        // Lay flat on the field, upright for the current camera side
        // (re-oriented by orientFieldText when the view flips for away games).
        textNode.name = "yardNumber"
        textNode.eulerAngles = SCNVector3(-Float.pi / 2, viewFacing >= 0 ? Float.pi : 0, 0)
        _ = facingLeft

        textNode.position = SCNVector3(x, 0.02, z)
        textNode.scale = SCNVector3(1, 1, 1)

        rootNode.addChildNode(textNode)
    }

    private func buildSidelines() {
        let halfWidth = FieldConstants.fieldWidth / 2
        let totalLen = FieldConstants.totalLength

        let lineGeometry = SCNBox(width: 0.15, height: 0.02, length: CGFloat(totalLen), chamferRadius: 0)
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = FieldColors.sideline
        lineGeometry.materials = [lineMaterial]

        let leftSideline = SCNNode(geometry: lineGeometry)
        leftSideline.position = SCNVector3(-halfWidth, 0.01, 0)
        rootNode.addChildNode(leftSideline)

        let rightSideline = SCNNode(geometry: lineGeometry)
        rightSideline.position = SCNVector3(halfWidth, 0.01, 0)
        rootNode.addChildNode(rightSideline)
    }

    // MARK: - Goalposts

    private func buildGoalposts() {
        let backLineZ = FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth
        for zSign: Float in [-1, 1] {
            rootNode.addChildNode(makeGoalpost(atZ: zSign * backLineZ))
        }
    }

    /// Simple NFL-style gooseneck goalpost: support post, crossbar, two uprights.
    private func makeGoalpost(atZ z: Float) -> SCNNode {
        let goldMaterial = SCNMaterial()
        goldMaterial.diffuse.contents = UIColor(red: 0.82, green: 0.70, blue: 0.22, alpha: 1)
        goldMaterial.roughness.contents = 0.55

        let crossbarHeight: Float = 3.3
        let crossbarWidth: Float = 6.2
        let uprightTop: Float = 9

        let post = SCNNode()
        post.name = "goalpost"
        post.position = SCNVector3(0, 0, z)

        // Gooseneck: single support post up to the crossbar
        let neckGeometry = SCNCylinder(radius: 0.22, height: CGFloat(crossbarHeight))
        neckGeometry.materials = [goldMaterial]
        let neckNode = SCNNode(geometry: neckGeometry)
        neckNode.position = SCNVector3(0, crossbarHeight / 2, 0)
        post.addChildNode(neckNode)

        // Crossbar spanning the two uprights
        let crossbarGeometry = SCNCylinder(radius: 0.17, height: CGFloat(crossbarWidth))
        crossbarGeometry.materials = [goldMaterial]
        let crossbarNode = SCNNode(geometry: crossbarGeometry)
        crossbarNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        crossbarNode.position = SCNVector3(0, crossbarHeight, 0)
        post.addChildNode(crossbarNode)

        // Two uprights
        let uprightHeight = uprightTop - crossbarHeight
        for xSign: Float in [-1, 1] {
            let uprightGeometry = SCNCylinder(radius: 0.15, height: CGFloat(uprightHeight))
            uprightGeometry.materials = [goldMaterial]
            let uprightNode = SCNNode(geometry: uprightGeometry)
            uprightNode.position = SCNVector3(
                xSign * crossbarWidth / 2,
                crossbarHeight + uprightHeight / 2,
                0
            )
            post.addChildNode(uprightNode)
        }

        return post
    }

    // MARK: - Pylons & Markers

    /// Low padded walls with a white lip finish the frame at the sidelines
    /// and the far end zone (the near end stays open for the camera).
    private func buildApronWalls() {
        let wallMaterial = SCNMaterial()
        wallMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.15, blue: 0.24, alpha: 1)
        let lipMaterial = SCNMaterial()
        lipMaterial.diffuse.contents = UIColor(white: 0.82, alpha: 1)

        let halfWidth = FieldConstants.fieldWidth / 2
        let halfLength = FieldConstants.totalLength / 2

        func addWall(width: CGFloat, length: CGFloat, at position: SCNVector3, name: String? = nil) {
            let container = SCNNode()
            container.name = name
            container.position = position

            let wallGeometry = SCNBox(width: width, height: 1.3, length: length, chamferRadius: 0.05)
            wallGeometry.materials = [wallMaterial]
            let wall = SCNNode(geometry: wallGeometry)
            container.addChildNode(wall)

            let lipGeometry = SCNBox(width: width + 0.1, height: 0.16, length: length + 0.1, chamferRadius: 0.05)
            lipGeometry.materials = [lipMaterial]
            let lip = SCNNode(geometry: lipGeometry)
            lip.position = SCNVector3(0, 0.7, 0)
            container.addChildNode(lip)

            rootNode.addChildNode(container)
        }

        // Dark apron strips ground the walls so the lips don't float in the void.
        let apronMaterial = SCNMaterial()
        apronMaterial.diffuse.contents = UIColor(red: 0.04, green: 0.10, blue: 0.05, alpha: 1)
        apronMaterial.roughness.contents = 1.0
        for xSign: Float in [-1, 1] {
            let apronGeometry = SCNBox(width: 9, height: 0.05,
                                       length: CGFloat(FieldConstants.totalLength + 14), chamferRadius: 0)
            apronGeometry.materials = [apronMaterial]
            let apron = SCNNode(geometry: apronGeometry)
            apron.position = SCNVector3(xSign * (halfWidth + 5.5), 0.02, 0)
            rootNode.addChildNode(apron)
        }

        for xSign: Float in [-1, 1] {
            addWall(width: 0.8, length: CGFloat(FieldConstants.totalLength + 12),
                    at: SCNVector3(xSign * (halfWidth + 6), 0.65, 0))
        }
        addWall(width: CGFloat(FieldConstants.fieldWidth + 13), length: 0.8,
                at: SCNVector3(0, 0.65, halfLength + 6), name: "endWallPos")
        addWall(width: CGFloat(FieldConstants.fieldWidth + 13), length: 0.8,
                at: SCNVector3(0, 0.65, -(halfLength + 6)), name: "endWallNeg")
        // The -Z wall would sit in front of the default (+facing) camera.
        rootNode.childNode(withName: "endWallNeg", recursively: false)?.isHidden = true
    }

    private func buildPylons() {
        let orange = SCNMaterial()
        orange.diffuse.contents = UIColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 1)
        let halfWidth = FieldConstants.fieldWidth / 2
        for zSign: Float in [-1, 1] {
            for xSign: Float in [-1, 1] {
                let geometry = SCNBox(width: 0.35, height: 0.9, length: 0.35, chamferRadius: 0.08)
                geometry.materials = [orange]
                let pylon = SCNNode(geometry: geometry)
                pylon.position = SCNVector3(xSign * halfWidth, 0.45, zSign * FieldConstants.fieldLength / 2)
                rootNode.addChildNode(pylon)
            }
        }
    }

    /// The broadcast LOS (blue) and first-down (yellow) stripes, hidden until
    /// `updateMarkers` places them.
    private func buildMarkers() {
        func makeMarker(color: UIColor) -> SCNNode {
            let geometry = SCNBox(width: CGFloat(FieldConstants.fieldWidth), height: 0.015, length: 0.55, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color.withAlphaComponent(0.35)
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.isHidden = true
            node.opacity = 0.55
            rootNode.addChildNode(node)
            return node
        }
        losMarkerNode = makeMarker(color: UIColor(red: 0.15, green: 0.35, blue: 0.95, alpha: 1))
        firstDownMarkerNode = makeMarker(color: UIColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1))
    }

    // MARK: - Ball

    private func buildBall() {
        if let kit = Self.playerKit {
            // Blender football with the lace strip baked in. The kit ball is
            // authored at true kit scale (half-length 0.17), so scale up
            // uniformly to the oversized broadcast-readable ball the old
            // ellipsoid was. Long axis = Z, matching the flight code: the
            // pass spiral (rotateBy z) spins around the seam axis and kicks
            // tumble end over end (rotateBy x) on the prolate shape.
            ballNode = instantiate(kit.football, name: "ball")
            ballNode.scale = SCNVector3(2.0, 2.0, 2.0)
        } else {
            let ballGeometry = SCNSphere(radius: CGFloat(FieldConstants.ballRadius))
            ballGeometry.segmentCount = 16

            // Stretch into an ellipsoid (football shape)
            let ballMaterial = SCNMaterial()
            ballMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1.0)
            ballMaterial.roughness.contents = 0.7
            ballGeometry.materials = [ballMaterial]

            ballNode = SCNNode(geometry: ballGeometry)
            ballNode.scale = SCNVector3(0.85, 0.85, 1.6)  // Elongate along Z

            // White laces stripes near each tip — reads as a football in flight.
            for zOffset: Float in [-0.16, 0.16] {
                let stripeGeometry = SCNTube(innerRadius: CGFloat(FieldConstants.ballRadius) * 0.98,
                                             outerRadius: CGFloat(FieldConstants.ballRadius) * 1.03,
                                             height: 0.05)
                let stripeMaterial = SCNMaterial()
                stripeMaterial.diffuse.contents = UIColor(white: 0.95, alpha: 1)
                stripeGeometry.materials = [stripeMaterial]
                let stripe = SCNNode(geometry: stripeGeometry)
                stripe.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                stripe.position = SCNVector3(0, 0, zOffset)
                stripe.scale = SCNVector3(1, 1, 0.75)
                ballNode.addChildNode(stripe)
            }
        }
        ballNode.position = SCNVector3(0, 0.3, 0)
        rootNode.addChildNode(ballNode)
    }

    // MARK: - Player Kit (Blender-authored parts)

    /// Prototype nodes for the Blender part kit (Resources/PlayerKit.usdc),
    /// loaded once per process and cloned per figure/ball. Each prototype is
    /// a named container whose inner "orient" node bakes the USD axis frame
    /// (meshes arrive Z-up, +Y-forward under a -90° X root rotation) into
    /// the scene's Y-up, +Z-facing figure frame — so the container itself
    /// can be positioned and rotated exactly like the old procedural nodes.
    /// Limb part origins sit at the segment TOP (the hinge), replacing the
    /// old capsule pivots: the node position IS the joint.
    private struct PlayerKitParts {
        let helmetShell: SCNNode
        let facemask: SCNNode
        let torso: SCNNode
        let thigh: SCNNode
        let shin: SCNNode
        let upperArm: SCNNode
        let forearm: SCNNode
        let cleat: SCNNode
        let football: SCNNode
    }

    /// nil (→ procedural fallback figures) when the resource is missing or
    /// SceneKit cannot parse it.
    private static let playerKit: PlayerKitParts? = loadPlayerKit()

    private static func loadPlayerKit() -> PlayerKitParts? {
        guard let url = Bundle.main.url(forResource: "PlayerKit", withExtension: "usdc") else {
            print("FootballFieldScene: PlayerKit.usdc not in bundle — procedural figures in use")
            return nil
        }
        guard let kitScene = try? SCNScene(url: url, options: nil) else {
            print("FootballFieldScene: PlayerKit.usdc failed to load — procedural figures in use")
            return nil
        }
        func part(_ name: String) -> SCNNode? {
            guard let found = kitScene.rootNode.childNode(withName: name, recursively: true) else {
                print("FootballFieldScene: PlayerKit.usdc missing part \(name) — procedural figures in use")
                return nil
            }
            let prototype = SCNNode()
            prototype.name = name
            let orient = SCNNode()
            // ZYX euler = Ry(π)·Rx(-π/2): mesh (x, y, z) → (-x, z, y) —
            // Blender up (+Z) becomes +Y, Blender front (+Y) becomes +Z.
            orient.eulerAngles = SCNVector3(-Float.pi / 2, Float.pi, 0)
            orient.addChildNode(found.clone())
            prototype.addChildNode(orient)
            return prototype
        }
        guard let helmetShell = part("HELMET_SHELL"),
              let facemask = part("FACEMASK"),
              let torso = part("TORSO"),
              let thigh = part("THIGH"),
              let shin = part("SHIN"),
              let upperArm = part("UPPER_ARM"),
              let forearm = part("FOREARM"),
              let cleat = part("CLEAT"),
              let football = part("FOOTBALL") else { return nil }
        print("FootballFieldScene: PlayerKit.usdc loaded (9 parts)")
        return PlayerKitParts(helmetShell: helmetShell, facemask: facemask, torso: torso,
                              thigh: thigh, shin: shin, upperArm: upperArm,
                              forearm: forearm, cleat: cleat, football: football)
    }

    /// Clones a kit prototype. All clones share the prototype's vertex data;
    /// when `override` swaps a slot material, the geometry is copied (an
    /// SCNGeometry copy still shares its sources) so the new materials apply
    /// per figure without touching other clones.
    private func instantiate(_ prototype: SCNNode,
                             name: String? = nil,
                             retint: ((SCNMaterial) -> SCNMaterial)? = nil) -> SCNNode {
        let node = prototype.clone()
        node.name = name
        if let retint {
            node.enumerateHierarchy { child, _ in
                guard let geometry = child.geometry else { return }
                let mapped = geometry.materials.map(retint)
                guard !zip(mapped, geometry.materials).allSatisfy({ $0 === $1 }),
                      let copy = geometry.copy() as? SCNGeometry else { return }
                copy.materials = mapped
                child.geometry = copy
            }
        }
        return node
    }

    /// Assembles the Blender part kit under `figure` with the same node
    /// names, joint positions and hinge origins as the procedural figure,
    /// so every animation (swingLimbs / reach / fall / throwMotion /
    /// resetGait / crouch stance) drives it unchanged.
    private func buildKitFigure(kit: PlayerKitParts, in figure: SCNNode,
                                uniform: Uniform, number: Int) {
        // Per-figure copies of the tintable slot materials, shared inside
        // the figure (torso + both upper arms share one JERSEY copy) so
        // applyUniform re-tints per team without cross-talk. MASK and SHOE
        // keep the shared prototype materials.
        let tints: [String: UIColor] = [
            "JERSEY": uniform.jersey,
            "PANTS": uniform.pants,
            "HELMET": uniform.helmet,
            "SKIN": Self.skinTones[number % Self.skinTones.count],
        ]
        var figureMaterials: [String: SCNMaterial] = [:]
        func retint(_ material: SCNMaterial) -> SCNMaterial {
            guard let slot = material.name, let color = tints[slot] else { return material }
            if let existing = figureMaterials[slot] { return existing }
            guard let copy = material.copy() as? SCNMaterial else { return material }
            copy.diffuse.contents = color
            figureMaterials[slot] = copy
            return copy
        }

        // Legs: thigh hinged at the hip, shin at the knee (kit origins sit
        // at the top of each segment — the same world hinge points the old
        // pivoted capsules used), cleat riding the ankle.
        for (index, xSign) in [Float(-1), 1].enumerated() {
            let leg = instantiate(kit.thigh, name: index == 0 ? "leg" : "legR", retint: retint)
            leg.position = SCNVector3(xSign * 0.14, 0.12, 0)
            figure.addChildNode(leg)

            let shin = instantiate(kit.shin, name: "shin", retint: retint)
            shin.position = SCNVector3(0, -0.51, 0)
            leg.addChildNode(shin)

            let cleat = instantiate(kit.cleat, name: "cleat")
            cleat.position = SCNVector3(0, -0.32, 0.05)
            shin.addChildNode(cleat)
        }

        // Torso: shoulder-pad silhouette, width/depth modeled into the mesh.
        let body = instantiate(kit.torso, name: "body", retint: retint)
        body.position = SCNVector3(0, 0.42, 0)
        figure.addChildNode(body)

        // Arms: hinged at the shoulder and elbow, resting slightly out.
        for (index, xSign) in [Float(-1), 1].enumerated() {
            let arm = instantiate(kit.upperArm, name: index == 0 ? "arm" : "armR", retint: retint)
            arm.position = SCNVector3(xSign * 0.38, 0.76, 0)
            arm.eulerAngles = SCNVector3(0, 0, xSign * -0.25)
            figure.addChildNode(arm)

            let forearm = instantiate(kit.forearm, name: "forearm", retint: retint)
            forearm.position = SCNVector3(0, -0.42, 0)
            forearm.eulerAngles = SCNVector3(-0.15, 0, 0)
            arm.addChildNode(forearm)
        }

        // Head: a simple skin sphere peeking out of the helmet's face opening.
        let headGeometry = SCNSphere(radius: 0.14)
        headGeometry.segmentCount = 10
        let headMaterial: SCNMaterial
        if let skin = figureMaterials["SKIN"] {
            headMaterial = skin
        } else {
            headMaterial = SCNMaterial()
            headMaterial.name = "SKIN"
            headMaterial.diffuse.contents = Self.skinTones[number % Self.skinTones.count]
            headMaterial.roughness.contents = 0.8
        }
        headGeometry.materials = [headMaterial]
        let head = SCNNode(geometry: headGeometry)
        head.position = SCNVector3(0, 0.97, 0)
        figure.addChildNode(head)

        // Helmet: shell + facemask cage grouped under the "helmet" node so
        // the whole assembly sits where the old helmet sphere was.
        let helmet = SCNNode()
        helmet.name = "helmet"
        helmet.position = SCNVector3(0, 1.04, 0)
        helmet.addChildNode(instantiate(kit.helmetShell, retint: retint))
        helmet.addChildNode(instantiate(kit.facemask))
        figure.addChildNode(helmet)
    }

    // MARK: - Players

    /// Realistic-ish skin tones, picked deterministically per jersey number.
    private static let skinTones: [UIColor] = [
        UIColor(red: 0.93, green: 0.76, blue: 0.63, alpha: 1),
        UIColor(red: 0.82, green: 0.62, blue: 0.46, alpha: 1),
        UIColor(red: 0.62, green: 0.42, blue: 0.29, alpha: 1),
        UIColor(red: 0.42, green: 0.28, blue: 0.19, alpha: 1),
    ]

    /// Builds a small stylized football player: legs, jersey torso with
    /// shoulder pads, arms, head and a helmet with a facemask, wearing a full
    /// NFL-convention uniform. The figure lives in a "figure" group node so
    /// the running gait (bob + lean) can animate it without fighting the
    /// container's position moves. Container origin sits at playerHeight/2
    /// above the turf, so the feet reach local -0.5.
    ///
    /// The body parts come from the Blender kit (PlayerKit.usdc) when it
    /// loads; otherwise the original procedural geometry is built. Both
    /// paths produce identical node names, joint positions and hinge
    /// origins, so all animation code works on either figure.
    private func makePlayerNode(uniform: Uniform, number: Int) -> SCNNode {
        let container = SCNNode()
        container.name = "player_\(number)"

        let figure = SCNNode()
        figure.name = "figure"
        // Chunky Madden-98 proportions: reads clearly from the pulled-back camera.
        figure.scale = SCNVector3(1.18, 1.18, 1.18)
        container.addChildNode(figure)

        // Blob shadow under the feet — the hard PSX-era drop shadow that
        // anchors every player to the turf.
        let shadowGeometry = SCNCylinder(radius: 0.42, height: 0.01)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = UIColor(white: 0, alpha: 0.38)
        shadowMaterial.lightingModel = .constant
        shadowGeometry.materials = [shadowMaterial]
        let shadow = SCNNode(geometry: shadowGeometry)
        shadow.name = "blobShadow"
        shadow.position = SCNVector3(0, -0.47, 0)
        shadow.castsShadow = false
        container.addChildNode(shadow)

        if let kit = Self.playerKit {
            buildKitFigure(kit: kit, in: figure, uniform: uniform, number: number)
        } else {
            buildProceduralFigure(in: figure, uniform: uniform, number: number)
        }

        // Jersey number text floating above
        let numberText = SCNText(string: "\(number)", extrusionDepth: 0.01)
        numberText.font = UIFont.systemFont(ofSize: 0.62, weight: .bold)
        numberText.flatness = 0.4

        let numberMaterial = SCNMaterial()
        numberMaterial.diffuse.contents = UIColor.white
        numberMaterial.emission.contents = UIColor(white: 0.35, alpha: 1.0)
        numberText.materials = [numberMaterial]

        let numberNode = SCNNode(geometry: numberText)
        numberNode.name = "number"

        // Center the number text
        let (minB, maxB) = numberNode.boundingBox
        numberNode.pivot = SCNMatrix4MakeTranslation(
            (maxB.x - minB.x) / 2 + minB.x,
            0,
            0
        )

        // Face the number toward the camera (angled up)
        numberNode.eulerAngles = SCNVector3(-Float.pi / 4, 0, 0)
        numberNode.position = SCNVector3(0, 1.35, 0)

        // Use billboard constraint so numbers always face the camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        numberNode.constraints = [billboardConstraint]

        container.addChildNode(numberNode)

        return container
    }

    /// The original procedural figure — the fallback when PlayerKit.usdc is
    /// unavailable. Materials carry the same slot names the kit uses so
    /// applyUniform re-tints both figure kinds identically.
    private func buildProceduralFigure(in figure: SCNNode, uniform: Uniform, number: Int) {
        // One shared jersey material so re-tinting the torso re-tints the arms.
        let jersey = SCNMaterial()
        jersey.name = "JERSEY"
        jersey.diffuse.contents = uniform.jersey
        jersey.roughness.contents = 0.6

        let pants = SCNMaterial()
        pants.name = "PANTS"
        pants.diffuse.contents = uniform.pants
        pants.roughness.contents = 0.7

        let skin = SCNMaterial()
        skin.name = "SKIN"
        skin.diffuse.contents = Self.skinTones[number % Self.skinTones.count]
        skin.roughness.contents = 0.8

        // Legs: two segments hinged at hip and knee, so the run cycle shows a
        // real bent-leg silhouette. Shared pants material re-tints everything.
        for (index, xSign) in [Float(-1), 1].enumerated() {
            let thighGeometry = SCNCapsule(capRadius: 0.09, height: 0.36)
            thighGeometry.radialSegmentCount = 8
            thighGeometry.materials = [pants]
            let hip = SCNNode(geometry: thighGeometry)
            hip.name = index == 0 ? "leg" : "legR"
            hip.pivot = SCNMatrix4MakeTranslation(0, 0.18, 0)
            hip.position = SCNVector3(xSign * 0.14, 0.12, 0)
            figure.addChildNode(hip)

            let shinGeometry = SCNCapsule(capRadius: 0.075, height: 0.34)
            shinGeometry.radialSegmentCount = 8
            shinGeometry.materials = [pants]
            let shin = SCNNode(geometry: shinGeometry)
            shin.name = "shin"
            shin.pivot = SCNMatrix4MakeTranslation(0, 0.17, 0)
            shin.position = SCNVector3(0, -0.33, 0)
            hip.addChildNode(shin)
        }

        // Torso: capsule squashed front-to-back and widened at the shoulders.
        let torsoGeometry = SCNCapsule(capRadius: 0.26, height: 0.85)
        torsoGeometry.radialSegmentCount = 10
        torsoGeometry.materials = [jersey]
        let torso = SCNNode(geometry: torsoGeometry)
        torso.name = "body"
        torso.position = SCNVector3(0, 0.42, 0)
        torso.scale = SCNVector3(1.25, 1.0, 0.85)
        figure.addChildNode(torso)

        // Arms: two segments hinged at shoulder and elbow — bent-arm pumping
        // while running, straight at rest.
        for (index, xSign) in [Float(-1), 1].enumerated() {
            let upperGeometry = SCNCapsule(capRadius: 0.075, height: 0.3)
            upperGeometry.radialSegmentCount = 8
            upperGeometry.materials = [jersey]
            let shoulder = SCNNode(geometry: upperGeometry)
            shoulder.name = index == 0 ? "arm" : "armR"
            shoulder.pivot = SCNMatrix4MakeTranslation(0, 0.15, 0)
            shoulder.position = SCNVector3(xSign * 0.38, 0.76, 0)
            shoulder.eulerAngles = SCNVector3(0, 0, xSign * -0.25)
            figure.addChildNode(shoulder)

            let forearmGeometry = SCNCapsule(capRadius: 0.065, height: 0.28)
            forearmGeometry.radialSegmentCount = 8
            forearmGeometry.materials = [skin]
            let forearm = SCNNode(geometry: forearmGeometry)
            forearm.name = "forearm"
            forearm.pivot = SCNMatrix4MakeTranslation(0, 0.14, 0)
            forearm.position = SCNVector3(0, -0.27, 0)
            forearm.eulerAngles = SCNVector3(-0.15, 0, 0)
            shoulder.addChildNode(forearm)
        }

        // Head + helmet
        let headGeometry = SCNSphere(radius: 0.14)
        headGeometry.segmentCount = 10
        headGeometry.materials = [skin]
        let head = SCNNode(geometry: headGeometry)
        head.position = SCNVector3(0, 0.97, 0)
        figure.addChildNode(head)

        let helmetGeometry = SCNSphere(radius: 0.165)
        helmetGeometry.segmentCount = 12
        let helmetMaterial = SCNMaterial()
        helmetMaterial.name = "HELMET"
        helmetMaterial.diffuse.contents = uniform.helmet
        helmetMaterial.roughness.contents = 0.3
        helmetGeometry.materials = [helmetMaterial]
        let helmet = SCNNode(geometry: helmetGeometry)
        helmet.name = "helmet"
        helmet.position = SCNVector3(0, 1.04, 0)
        // Open the helmet at the face: shift it slightly up-back so the skin
        // sphere peeks out at the front.
        helmet.scale = SCNVector3(1.0, 0.95, 1.05)
        figure.addChildNode(helmet)

        // Facemask: a gray bar across the front of the helmet (+Z = facing).
        let maskGeometry = SCNBox(width: 0.2, height: 0.045, length: 0.05, chamferRadius: 0.02)
        let maskMaterial = SCNMaterial()
        maskMaterial.diffuse.contents = UIColor(white: 0.7, alpha: 1)
        maskMaterial.roughness.contents = 0.4
        maskGeometry.materials = [maskMaterial]
        let mask = SCNNode(geometry: maskGeometry)
        mask.position = SCNVector3(0, 0.99, 0.15)
        figure.addChildNode(mask)
    }

    private func darkenColor(_ color: UIColor, by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: max(r - amount, 0),
            green: max(g - amount, 0),
            blue: max(b - amount, 0),
            alpha: a
        )
    }

    // MARK: - Camera

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 52
        camera.zNear = 1
        camera.zFar = 300
        camera.wantsHDR = true

        cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        cameraNode.camera = camera

        // Position above the field, looking down at ~60 degree angle
        // Slightly offset toward one end zone for a broadcast-style angle
        cameraNode.position = SCNVector3(0, 80, 55)

        // Invisible target the LookAt constraint tracks, so focusCamera(z:)
        // can pan the view along the field during play sequences.
        cameraTargetNode = SCNNode()
        cameraTargetNode.name = "cameraTarget"
        cameraTargetNode.position = SCNVector3(0, 0, 0)
        rootNode.addChildNode(cameraTargetNode)

        let lookAtConstraint = SCNLookAtConstraint(target: cameraTargetNode)
        lookAtConstraint.isGimbalLockEnabled = true
        cameraNode.constraints = [lookAtConstraint]

        rootNode.addChildNode(cameraNode)
    }

    // MARK: - Lighting

    private func buildLighting() {
        // Main stadium light: directional from above
        let mainLight = SCNLight()
        mainLight.type = .directional
        mainLight.color = UIColor(white: 0.95, alpha: 1.0)
        mainLight.intensity = 1200
        mainLight.castsShadow = true
        mainLight.shadowMode = .deferred
        mainLight.shadowColor = UIColor(white: 0, alpha: 0.35)
        mainLight.shadowRadius = 4
        mainLight.shadowMapSize = CGSize(width: 2048, height: 2048)

        let mainLightNode = SCNNode()
        mainLightNode.name = "mainLight"
        mainLightNode.light = mainLight
        mainLightNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        mainLightNode.position = SCNVector3(0, 100, 0)
        rootNode.addChildNode(mainLightNode)

        // Fill light from opposite side (softer)
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.color = UIColor(white: 0.85, alpha: 1.0)
        fillLight.intensity = 400
        fillLight.castsShadow = false

        let fillLightNode = SCNNode()
        fillLightNode.name = "fillLight"
        fillLightNode.light = fillLight
        fillLightNode.eulerAngles = SCNVector3(-Float.pi / 4, -Float.pi / 4, 0)
        rootNode.addChildNode(fillLightNode)

        // Ambient fill so nothing is pure black
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.25, alpha: 1.0)
        ambientLight.intensity = 500

        let ambientLightNode = SCNNode()
        ambientLightNode.name = "ambientLight"
        ambientLightNode.light = ambientLight
        rootNode.addChildNode(ambientLightNode)
    }

    // MARK: - Weather

    /// Applies a visual weather treatment over the field. Idempotent: any
    /// previous weather visuals are removed first, and the lighting returns
    /// to its defaults before the new condition is applied.
    ///
    /// - rain: procedural streak particles falling from above + dimmer lights
    /// - snow: slow white flakes + a faint snow blanket over the turf
    /// - wind/clear: no visuals (gusts would just read as noise from this camera)
    func setWeather(_ weather: GameWeather) {
        rootNode.childNode(withName: "weatherEmitter", recursively: false)?.removeFromParentNode()
        rootNode.childNode(withName: "snowBlanket", recursively: false)?.removeFromParentNode()
        setLightIntensities(main: 1200, fill: 400, ambient: 500)

        switch weather {
        case .clear, .wind:
            break
        case .rain:
            addWeatherEmitter(Self.rainSystem())
            setLightIntensities(main: 850, fill: 300, ambient: 420)
        case .snow:
            addWeatherEmitter(Self.snowSystem())
            addSnowBlanket()
            setLightIntensities(main: 1200, fill: 400, ambient: 620)
        }
    }

    private func setLightIntensities(main: CGFloat, fill: CGFloat, ambient: CGFloat) {
        rootNode.childNode(withName: "mainLight", recursively: false)?.light?.intensity = main
        rootNode.childNode(withName: "fillLight", recursively: false)?.light?.intensity = fill
        rootNode.childNode(withName: "ambientLight", recursively: false)?.light?.intensity = ambient
    }

    /// Adds the particle emitter high above the field, covering the whole
    /// playing surface plus the aprons.
    private func addWeatherEmitter(_ system: SCNParticleSystem) {
        let node = SCNNode()
        node.name = "weatherEmitter"
        node.position = SCNVector3(0, 32, 0)
        node.addParticleSystem(system)
        rootNode.addChildNode(node)
    }

    /// Faint white translucent sheet just above the turf (below the painted
    /// yard lines' top face at y 0.02) — reads as light snow cover.
    private func addSnowBlanket() {
        let blanket = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth + 8),
            height: 0.002,
            length: CGFloat(FieldConstants.totalLength + 8),
            chamferRadius: 0
        )
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 1.0, alpha: 0.15)
        material.lightingModel = .constant
        blanket.materials = [material]

        let node = SCNNode(geometry: blanket)
        node.name = "snowBlanket"
        node.position = SCNVector3(0, 0.014, 0)
        rootNode.addChildNode(node)
    }

    /// Procedural rain: small stretched streaks falling straight down at
    /// speed, tinted cool and slightly additive so they catch the lights.
    private static func rainSystem() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 400
        system.particleLifeSpan = 1.6
        system.emitterShape = SCNBox(width: 70, height: 0.5, length: 130, chamferRadius: 0)
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, -1, 0)
        system.spreadingAngle = 2
        system.particleVelocity = 24
        system.particleVelocityVariation = 6
        system.particleImage = rainStreakImage()
        system.particleSize = 0.32
        system.particleSizeVariation = 0.12
        system.particleColor = UIColor(red: 0.65, green: 0.72, blue: 0.85, alpha: 0.3)
        system.blendMode = .additive
        system.stretchFactor = 0.06
        system.isLightingEnabled = false
        return system
    }

    /// Procedural snow: slow, drifting white flakes with a long lifespan so
    /// they cover the full drop from the emitter to the turf.
    private static func snowSystem() -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 220
        system.particleLifeSpan = 16
        system.emitterShape = SCNBox(width: 70, height: 0.5, length: 130, chamferRadius: 0)
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, -1, 0)
        system.spreadingAngle = 14
        system.particleVelocity = 2.4
        system.particleVelocityVariation = 0.8
        system.particleImage = snowflakeImage()
        system.particleSize = 0.18
        system.particleSizeVariation = 0.08
        system.particleColor = UIColor(white: 1.0, alpha: 0.9)
        system.isLightingEnabled = false
        return system
    }

    /// Tiny vertical white streak — the rain drop sprite, drawn in code.
    private static func rainStreakImage() -> UIImage {
        let size = CGSize(width: 6, height: 32)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(
                roundedRect: CGRect(x: 2, y: 0, width: 2, height: 32),
                cornerRadius: 1
            ).fill()
        }
    }

    /// Soft white dot — the snowflake sprite, drawn in code.
    private static func snowflakeImage() -> UIImage {
        let size = CGSize(width: 16, height: 16)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 12, height: 12)).fill()
        }
    }
}
