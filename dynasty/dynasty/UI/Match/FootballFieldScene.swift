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
        static let grass = UIColor(red: 0.15, green: 0.45, blue: 0.15, alpha: 1.0)
        static let endZone = UIColor(red: 0.10, green: 0.32, blue: 0.10, alpha: 1.0)
        static let yardLine = UIColor.white
        static let numbers = UIColor(white: 1.0, alpha: 0.85)
        static let sideline = UIColor.white
        static let fieldBorder = UIColor(red: 0.08, green: 0.25, blue: 0.08, alpha: 1.0)
    }

    // MARK: - Properties

    private(set) var cameraNode: SCNNode = SCNNode()
    private var homePlayerNodes: [SCNNode] = []
    private var awayPlayerNodes: [SCNNode] = []
    private var ballNode: SCNNode = SCNNode()
    private var homeColor: UIColor = UIColor.blue
    private var awayColor: UIColor = UIColor.red

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
        buildEndZones()
        buildYardLines()
        buildNumbers()
        buildHashMarks()
        buildSidelines()
        buildBall()
        buildCamera()
        buildLighting()
    }

    /// Sets the home team uniform color and updates existing player nodes.
    func setHomeTeamColor(_ color: UIColor) {
        homeColor = color
        for node in homePlayerNodes {
            if let body = node.childNode(withName: "body", recursively: false) {
                body.geometry?.firstMaterial?.diffuse.contents = color
            }
        }
    }

    /// Sets the away team uniform color and updates existing player nodes.
    func setAwayTeamColor(_ color: UIColor) {
        awayColor = color
        for node in awayPlayerNodes {
            if let body = node.childNode(withName: "body", recursively: false) {
                body.geometry?.firstMaterial?.diffuse.contents = color
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

        for info in home {
            let node = makePlayerNode(color: homeColor, number: info.number)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            rootNode.addChildNode(node)
            homePlayerNodes.append(node)
        }

        for info in away {
            let node = makePlayerNode(color: awayColor, number: info.number)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
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

    // MARK: - Field Construction

    private func buildFieldSurface() {
        // Main playing field
        let fieldGeometry = SCNBox(
            width: CGFloat(FieldConstants.fieldWidth),
            height: CGFloat(FieldConstants.fieldThickness),
            length: CGFloat(FieldConstants.fieldLength),
            chamferRadius: 0
        )
        let grassMaterial = SCNMaterial()
        grassMaterial.diffuse.contents = FieldColors.grass
        grassMaterial.roughness.contents = 0.9
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

    private func buildEndZones() {
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

        // Home end zone (negative Z)
        let homeEndZone = SCNNode(geometry: endZoneGeometry)
        homeEndZone.position = SCNVector3(
            0,
            -FieldConstants.fieldThickness / 2 + 0.01,
            -(FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth / 2)
        )
        rootNode.addChildNode(homeEndZone)

        // Away end zone (positive Z)
        let awayEndZone = SCNNode(geometry: endZoneGeometry)
        awayEndZone.position = SCNVector3(
            0,
            -FieldConstants.fieldThickness / 2 + 0.01,
            FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth / 2
        )
        rootNode.addChildNode(awayEndZone)

        // End zone back lines
        for zSign: Float in [-1, 1] {
            let lineZ = zSign * (FieldConstants.fieldLength / 2 + FieldConstants.endZoneDepth)
            addYardLine(atZ: lineZ, thickness: 0.15)
        }
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

        // Lay flat on field, rotated to read from sideline
        textNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)

        // Rotate based on which side of the field
        if facingLeft {
            textNode.eulerAngles.y = Float.pi
        }

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

    // MARK: - Ball

    private func buildBall() {
        let ballGeometry = SCNSphere(radius: CGFloat(FieldConstants.ballRadius))
        ballGeometry.segmentCount = 16

        // Stretch into an ellipsoid (football shape)
        let ballMaterial = SCNMaterial()
        ballMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.27, blue: 0.07, alpha: 1.0)
        ballMaterial.roughness.contents = 0.7
        ballGeometry.materials = [ballMaterial]

        ballNode = SCNNode(geometry: ballGeometry)
        ballNode.scale = SCNVector3(0.8, 0.8, 1.5)  // Elongate along Z
        ballNode.position = SCNVector3(0, 0.3, 0)
        rootNode.addChildNode(ballNode)
    }

    // MARK: - Players

    private func makePlayerNode(color: UIColor, number: Int) -> SCNNode {
        let container = SCNNode()
        container.name = "player_\(number)"

        // Body: capsule
        let bodyGeometry = SCNCapsule(
            capRadius: CGFloat(FieldConstants.playerRadius),
            height: CGFloat(FieldConstants.playerHeight)
        )
        bodyGeometry.radialSegmentCount = 12
        let bodyMaterial = SCNMaterial()
        bodyMaterial.diffuse.contents = color
        bodyMaterial.roughness.contents = 0.6
        bodyGeometry.materials = [bodyMaterial]

        let bodyNode = SCNNode(geometry: bodyGeometry)
        bodyNode.name = "body"
        container.addChildNode(bodyNode)

        // Helmet: small sphere on top
        let helmetGeometry = SCNSphere(radius: CGFloat(FieldConstants.playerRadius * 0.65))
        helmetGeometry.segmentCount = 12
        let helmetMaterial = SCNMaterial()
        helmetMaterial.diffuse.contents = darkenColor(color, by: 0.3)
        helmetGeometry.materials = [helmetMaterial]

        let helmetNode = SCNNode(geometry: helmetGeometry)
        helmetNode.position = SCNVector3(0, FieldConstants.playerHeight * 0.4, 0)
        container.addChildNode(helmetNode)

        // Jersey number text floating above
        let numberText = SCNText(string: "\(number)", extrusionDepth: 0.01)
        numberText.font = UIFont.systemFont(ofSize: 0.8, weight: .bold)
        numberText.flatness = 0.4

        let numberMaterial = SCNMaterial()
        numberMaterial.diffuse.contents = UIColor.white
        numberMaterial.emission.contents = UIColor(white: 0.5, alpha: 1.0)
        numberText.materials = [numberMaterial]

        let numberNode = SCNNode(geometry: numberText)

        // Center the number text
        let (minB, maxB) = numberNode.boundingBox
        numberNode.pivot = SCNMatrix4MakeTranslation(
            (maxB.x - minB.x) / 2 + minB.x,
            0,
            0
        )

        // Face the number toward the camera (angled up)
        numberNode.eulerAngles = SCNVector3(-Float.pi / 4, 0, 0)
        numberNode.position = SCNVector3(0, FieldConstants.playerHeight * 0.7, 0)

        // Use billboard constraint so numbers always face the camera
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        numberNode.constraints = [billboardConstraint]

        container.addChildNode(numberNode)

        return container
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
        camera.fieldOfView = 45
        camera.zNear = 1
        camera.zFar = 300
        camera.wantsHDR = true

        cameraNode = SCNNode()
        cameraNode.name = "mainCamera"
        cameraNode.camera = camera

        // Position above the field, looking down at ~60 degree angle
        // Slightly offset toward one end zone for a broadcast-style angle
        cameraNode.position = SCNVector3(0, 80, 55)

        // Look at center of field
        let lookAtConstraint = SCNLookAtConstraint(target: rootNode)
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
        fillLightNode.light = fillLight
        fillLightNode.eulerAngles = SCNVector3(-Float.pi / 4, -Float.pi / 4, 0)
        rootNode.addChildNode(fillLightNode)

        // Ambient fill so nothing is pure black
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.25, alpha: 1.0)
        ambientLight.intensity = 500

        let ambientLightNode = SCNNode()
        ambientLightNode.light = ambientLight
        rootNode.addChildNode(ambientLightNode)
    }
}
