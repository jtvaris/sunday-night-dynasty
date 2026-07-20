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
        /// Animation Overhaul (Option A): drive players with skinned skeletal
        /// clips instead of the procedural joint-rotation figure, when the rig
        /// asset is present. Falls back to the kit/procedural figure otherwise.
        /// See docs/ANIMATION_OVERHAUL_PLAN.md.
        static var useSkeletalFigures: Bool { SkeletalFigure.isAvailable }
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
        /// Waypoint runs (route running): the node sprints through each point
        /// in order within this step, leg times split by distance so speed
        /// stays constant through the cuts. A node with a path this step must
        /// not also appear in `moves`.
        var paths: [(nodeIndex: Int, points: [SCNVector3], duration: TimeInterval)] = []
        /// Optional ball behavior for this step.
        var ballMove: BallMove?
        /// Minimum length of the step in seconds.
        var duration: TimeInterval
        /// Player nodes to pulse (brief scale-up) when the step begins.
        var pulses: [Int] = []
        /// Player nodes that go to the ground when the step begins (tackles).
        var falls: [Int] = []
        /// Player nodes whose arms wrap around the man they're hitting when
        /// the step begins (wrap tackles — pair with `falls` or a drive-back).
        var wraps: [Int] = []
        /// Player nodes that throw their arms up when the step begins (catches).
        var reaches: [Int] = []
        /// Player nodes whose moves this step are backpedals: they keep facing
        /// downfield while moving backwards (QB dropbacks).
        var backpedals: [Int] = []
        /// Player nodes that leap into a touchdown celebration this step.
        var celebrates: [Int] = []
        /// Player nodes locked into a blocking engagement this step: the arms
        /// punch out at chest height and the figure works a short fore-aft
        /// shove cycle — OL/DL pairs read as locked up, not jogging to spots.
        var blocks: [Int] = []
        /// QB nodes selling a pump fake late in this step (deep shots).
        var pumpFakes: [Int] = []
        /// When true, the pump fake is a quick shoulder shrug rather than a
        /// full wind-up double-clutch (mobile QBs flash the short version).
        var pumpFakeQuick: Bool = false
        /// The passer's throwing motion when this step's ball arc is a real
        /// pass. nil = the default over-the-top overhand.
        var throwStyle: ThrowStyle? = nil
        /// Catch presentation per reaching node (missing = the basic reach).
        var catchStyles: [Int: CatchStyle] = [:]
        /// Carriers blown off their feet by a big hit this step: they fly
        /// backward onto their back (pair with a backward move) + camera bump.
        var bigHits: [Int] = []
        /// Tacklers finishing with a flat horizontal dive at the carrier's legs.
        var diveFalls: [Int] = []
        /// Carriers whose legs get cut out (shoestring/ankle tackle): they
        /// pitch forward and stumble to the turf instead of a clean collapse.
        var trips: [Int] = []
        /// Ball carriers laying out into the end zone with the ball extended
        /// over the pylon (goal-line dives) — they stretch out and stay down.
        var pylonDives: [Int] = []
        /// A QB giving himself up feet-first with a protective slide (scrambles).
        var qbSlides: [Int] = []
        /// Ball carriers stretching the ball forward on a lunge — reaching the
        /// first-down marker / goal line as they go down.
        var lunges: [Int] = []
        /// Per-node blocking-engagement style (missing = a plain drive block).
        var blockStyles: [Int: BlockStyle] = [:]
        /// Scheduled jukes/spins/stiff-arms for ball carriers inside this step.
        var openField: [OpenFieldMove] = []
        /// Per-node reaction delays (seconds from step start) before that
        /// node's move/path launches — staggered get-offs at the snap so the
        /// 22 never fire in lockstep. Small (≤0.3 s); a late mover simply
        /// bleeds into the next step, where his next move takes over.
        var startDelays: [Int: TimeInterval] = [:]
        /// Explicit SFX cue fired when the step begins (kick thumps, long
        /// snaps). Snap/hit/catch sounds are derived automatically from the
        /// step's ball move and contact lists — this slot is for beats the
        /// scene can't infer.
        var sound: MatchSound? = nil
    }

    /// How a receiver plays the ball at the catch point.
    enum CatchStyle {
        /// The basic hands-up catch (default).
        case reach
        /// Deep ball tracked over the shoulder on the run: arms up and
        /// forward along the route instead of straight overhead.
        case overShoulder
        /// Full-extension diving grab — tight coverage, ball barely arrives.
        case dive
        /// Sideline grab with quick toe taps to get the feet down in bounds.
        case toeTap
    }

    /// How an OL/DL figure plays out a blocking engagement. Chosen from the
    /// trench matchup so the winning side visibly wins the rep.
    enum BlockStyle {
        /// Winner presses forward in short surges (the base run block).
        case drive
        /// Pass-pro set: absorb the bull rush, give a little ground, re-anchor.
        case anchor
        /// Decisive win: the blocker lunges forward and drives his man down.
        case pancake
        /// Beaten: a swim/rip over the top as his man slips past, half a turn.
        case whiff
        /// Cut block: down at the legs, then back up.
        case cut
    }

    /// A scheduled open-field move for a ball carrier mid-step.
    /// `delay` is seconds from the step start.
    struct OpenFieldMove {
        enum Kind {
            /// Sharp jab-step side-step feint (pairs with a lateral jig in the
            /// path) — a hard plant one way sold by a quick lateral hop.
            case juke
            /// Full 360° spin, dipping and rising out of the turn.
            case spin
            /// Off arm extended into the nearest chaser, with a lean into it.
            case stiffArm
            /// Hurdle: a short leap with the knees tucked (power backs jumping
            /// a fallen defender).
            case hurdle
            /// Dead-leg / hesitation: a quick stutter-hitch that freezes the
            /// pursuit before the carrier bursts back to speed.
            case deadLeg
        }
        var nodeIndex: Int
        var kind: Kind
        var delay: TimeInterval
    }

    /// How the passer's arm and body drive a throw. Chosen deterministically
    /// from the QB and the situation so a given passer keeps a signature.
    enum ThrowStyle {
        /// Clean over-the-top base motion — the default.
        case overhand
        /// 3/4 sidearm flick: elbow drops out, quick short release.
        case sidearm
        /// Off the back foot under pressure/scramble: unbalanced, no weight
        /// transfer, the trunk bails away instead of driving forward.
        case offFoot
        /// Deep touch throw: a big wind-up and a slow, high follow-through.
        case lob
        /// Deep drive: full wind-up snapped through on a fast, flat release.
        case bullet
    }

    /// How the ball behaves during a `PlayStep`.
    enum BallMove {
        /// Ball rides with the given player node (0-10 home, 11-21 away),
        /// tucked under the carrier's arm.
        case carry(nodeIndex: Int)
        /// Ball rides with the given player held at the chest in both hands —
        /// the QB's dropback carry before the throw.
        case carryChest(nodeIndex: Int)
        /// The C→QB exchange at the snap: under center the ball transfers
        /// hand to hand; shotgun lofts a low toss back to the QB. The ball
        /// homes on the QB node (he may already be moving) and attaches into
        /// the chest carry on arrival.
        case snap(toNodeIndex: Int, shotgun: Bool)
        /// Ball flies a parabolic arc to the target with the given apex height.
        /// `from` names the passer/pitcher so the flight can always launch
        /// from his hands even if a snap→throw race left the carry briefly
        /// unassigned; nil for a kick (the ball leaves the spot it sits on).
        case arc(to: SCNVector3, apex: Float, duration: TimeInterval, from: Int?)
        /// Ball moves flat along the ground (snaps, rolls, dead balls).
        case slide(to: SCNVector3, duration: TimeInterval)
    }

    /// Flight time of the C→QB exchange.
    static func snapDuration(shotgun: Bool) -> TimeInterval {
        shotgun ? 0.42 : 0.2
    }

    // MARK: - Uniforms

    /// A full NFL-convention uniform: jersey, pants, and helmet colors, plus
    /// the trim details the close coach camera reads — the raw team color
    /// (`accent`, drives sleeve stripes and socks), the team abbreviation
    /// (helmet side decals) and an optional team-colored facemask.
    struct Uniform {
        var jersey: UIColor
        var pants: UIColor
        var helmet: UIColor
        /// The raw team color regardless of which garment carries it —
        /// sleeve stripes and socks contrast against jersey/pants with it.
        var accent: UIColor = UIColor(white: 0.9, alpha: 1)
        /// Team abbreviation for the helmet side decals ("" = no decal,
        /// which keeps the legacy far-camera MatchView untouched).
        var abbreviation: String = ""
        /// Team-colored facemask (~40 % of teams, deterministic from the
        /// abbreviation); nil keeps the kit's gray cage.
        var facemask: UIColor? = nil

        /// Home teams wear their color; road teams wear white with team-color
        /// pants and helmet — instant NFL reading and guaranteed contrast.
        /// Helmets run a shade darker than the jersey so heads read as gear.
        static func home(teamColor: UIColor, abbreviation: String = "") -> Uniform {
            Uniform(jersey: teamColor,
                    pants: UIColor(white: 0.88, alpha: 1),
                    helmet: shaded(teamColor),
                    accent: teamColor,
                    abbreviation: abbreviation,
                    facemask: facemaskColor(teamColor: teamColor, abbreviation: abbreviation))
        }

        static func away(teamColor: UIColor, abbreviation: String = "") -> Uniform {
            Uniform(jersey: UIColor(white: 0.93, alpha: 1),
                    pants: teamColor,
                    helmet: shaded(teamColor),
                    accent: teamColor,
                    abbreviation: abbreviation,
                    facemask: facemaskColor(teamColor: teamColor, abbreviation: abbreviation))
        }

        private static func shaded(_ color: UIColor) -> UIColor {
            var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: max(r - 0.2, 0), green: max(g - 0.2, 0),
                           blue: max(b - 0.2, 0), alpha: a)
        }

        /// ~40 % of teams run a team-colored cage instead of gray —
        /// deterministic from the abbreviation so a team's look never flips
        /// between games.
        private static func facemaskColor(teamColor: UIColor, abbreviation: String) -> UIColor? {
            guard !abbreviation.isEmpty else { return nil }
            let hash = abbreviation.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
            return abs(hash) % 10 < 4 ? teamColor : nil
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
    /// The back judge standing behind the play — pure dressing (see buildReferee).
    private var refereeNode: SCNNode?
    /// Last known offense drive direction (+1 toward +Z); keeps the referee
    /// on the right side of the ball when a goal-to-go snap hides the stripe.
    private var refereeDirection: Float = 1
    /// Node index currently carrying the ball (for the arm-tuck pose).
    private var carryingIndex: Int?
    /// True while the current carrier holds the ball at his chest in both
    /// hands (QB dropback) instead of the under-arm tuck.
    private var carryingChest = false
    /// Bumped by every ball transition (snap, carry, arc, slide). A snap's
    /// asynchronous carry-attach captures the token and no-ops if a later
    /// move already claimed the ball — this kills the snap→throw race that
    /// otherwise launched a pass before the carry was assigned.
    private var ballHandoffToken = 0

    /// How a moving player's arms handle the ball, for the gait cycle.
    private enum CarryStyle {
        case none, tucked, chest
    }

    /// The carry style `node` runs with right now.
    private func carryStyle(of node: SCNNode) -> CarryStyle {
        guard playerNode(at: carryingIndex ?? -1) === node else { return .none }
        return carryingChest ? .chest : .tucked
    }
    /// Camera's current focus Z, so the follow-cam can decide when to pan.
    private var focusZ: Float = 0
    /// While true the kick camera owns the shot: the follow-cam in `execute`
    /// stays parked so the ball arcs toward the lens. Any `focusCamera` call
    /// hands the shot back.
    private var kickCameraActive = false
    /// The camera's aim constraint, kept so the replay camera can restore it
    /// after swapping in its per-frame follower constraints.
    private var cameraLookAtConstraint: SCNLookAtConstraint?

    // MARK: Camera style

    /// How close the scrimmage shot sits.
    enum CameraStyle: String {
        /// Madden-scale coach shot: low behind the offense (or the defensive
        /// box), long lens — the foreground back fills ~a third of the frame.
        case coach
        /// The pulled-back high broadcast framing (the pre-R15 default).
        case broadcast
    }

    /// The user's chosen scrimmage framing. Defaults to `.broadcast` so the
    /// legacy MatchView (which never focuses the camera) keeps its far shot;
    /// CoachedGameView switches it to the persisted Coach/Broadcast choice.
    private(set) var cameraStyle: CameraStyle = .broadcast

    /// The style of the shot currently on screen. Kickoffs force a broadcast
    /// shot even in coach mode (`focusCamera(style:)` override) and the
    /// follow-cam must keep panning in that same framing mid-play.
    private var currentShotStyle: CameraStyle = .broadcast

    // MARK: Live follow-cam (continuous, per-frame)

    /// While true the live-play follow rig owns the shot: per-frame
    /// constraints glide the aim point (and the camera, at its style offset)
    /// with the ball, replay-truck style. Runs for every live play in both
    /// framings; kicks and replays keep their own shots.
    private var liveFollowActive = false
    /// The LOS framing z when the follow began — progress is measured from
    /// here so the pre-snap composition holds through the dropback.
    private var followAnchorZ: Float = 0
    /// Forward ratchet (yards of progress along the play's attack direction).
    /// Follows the ball downfield immediately; backward only with ~6 yd of
    /// slack, so a dropback doesn't pump the frame but a kick return running
    /// the other way still drags the camera along. Mutated on the render
    /// thread inside the follow constraints only.
    private var followProgress: Float = 0

    /// Switches the scrimmage framing and (unless a kick shot owns the
    /// camera) glides the current shot into the new style. The floating
    /// billboard numbers dim with the framing — see billboardNumberOpacity.
    func setCameraStyle(_ style: CameraStyle, refocus: Bool = true) {
        guard style != cameraStyle else { return }
        cameraStyle = style
        applyBillboardNumberVisibility()
        guard refocus, !kickCameraActive else { return }
        focusCamera(z: focusZ, animated: true, duration: 0.7)
    }

    /// Billboard numbers: 0.6 opacity long-range aid in broadcast, much
    /// dimmer in the elevated coach shot — the jersey decals carry the read
    /// there, and at 0.35 the floating digits projected onto the turf (and
    /// onto the players behind them) from the low angle as ghost numbers.
    private var billboardNumberOpacity: CGFloat {
        cameraStyle == .coach ? 0.2 : 0.6
    }

    private func applyBillboardNumberVisibility() {
        for node in homePlayerNodes + awayPlayerNodes {
            node.childNode(withName: "number", recursively: false)?.opacity = billboardNumberOpacity
        }
    }
    /// Incremented on every runPlay/cancelPlay so stale scheduled steps become no-ops.
    private var playGeneration = 0

    // MARK: - R39: Background GPU warm-up

    /// Compiles the field's Metal pipelines, geometry and the player-kit
    /// figures ONCE in the background, so the first "Coach the Game" open
    /// doesn't pay SceneKit's first-render shader compile (the dominant part
    /// of the measured 1.6 s tap→first-frame latency; scene construction
    /// itself is only ~30 ms).
    ///
    /// Safe off-main: the throwaway scene is never attached to a view, and
    /// SceneKit's shader/pipeline caches are process-wide, so the real
    /// coached-game SCNView reuses everything compiled here. Runs at most
    /// once per launch; called from the career dashboard's `.task`.
    private static var didWarmUp = false

    static func warmUp() {
        guard !didWarmUp else { return }
        didWarmUp = true
        DispatchQueue.global(qos: .utility).async {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            let start = CFAbsoluteTimeGetCurrent()
            let scene = FootballFieldScene()
            // Spawn both squads (teleport path) so the kit-figure geometry
            // and JERSEY/PANTS/HELMET/SKIN materials compile too.
            let home = (0..<11).map { (x: Float($0) * 2 - 10, z: Float(-3), number: $0 + 1) }
            let away = (0..<11).map { (x: Float($0) * 2 - 10, z: Float(3), number: $0 + 12) }
            scene.movePlayersToFormation(home: home, away: away, duration: 0)
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            // Uploads geometry + textures to the GPU. (A full offscreen
            // render was tried too — it compiles pipeline states in ~850 ms,
            // but SCNView does not reuse them, so the extra GPU work bought
            // nothing; measured first-frame stayed ~1.5 s either way.)
            renderer.prepare([scene.rootNode]) { _ in
                #if DEBUG
                print(String(format: "PERF|scene_warmup|%.1f",
                             (CFAbsoluteTimeGetCurrent() - start) * 1000))
                #endif
            }
        }
    }

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
        var perf = PerfLog.Lap("scene_setup")   // R39 startup breakdown
        // Clear any existing nodes
        rootNode.childNodes.forEach { $0.removeFromParentNode() }
        homePlayerNodes.removeAll()
        awayPlayerNodes.removeAll()

        buildFieldSurface()
        buildMowingStripes()
        buildEndZones()
        buildYardLines()
        perf.lap("surfaces_lines")
        buildNumbers()
        perf.lap("numbers")
        buildHashMarks()
        buildSidelines()
        buildGoalposts()
        buildPylons()
        buildApronWalls()
        buildStadium()
        buildMarkers()
        perf.lap("dressing")
        buildReferee()
        buildBall()
        buildCamera()
        buildLighting()
        perf.lap("figures_misc")

        // Depth falloff: the far field darkens into the night like a
        // low-slung TV camera shot. Weather re-tunes this in setWeather().
        applyFog(color: Self.clearFogColor, start: 70, end: 210)
        startIdleSweep()
        perf.finish()
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
            // The helmet side decals only show when the uniform carries an
            // abbreviation (the legacy quick-match path passes none).
            if child.name == "helmetDecal" {
                child.isHidden = uniform.abbreviation.isEmpty
            }
            guard let materials = child.geometry?.materials else { return }
            for material in materials {
                switch material.name {
                case "JERSEY": material.diffuse.contents = uniform.jersey
                case "PANTS": material.diffuse.contents = uniform.pants
                case "HELMET": material.diffuse.contents = uniform.helmet
                case "STRIPE": material.diffuse.contents = Self.stripeColor(for: uniform)
                case "SOCK": material.diffuse.contents = Self.sockColor(for: uniform)
                case "MASK":
                    // Kit figures carry per-figure MASK copies (see
                    // buildKitFigure), so team cages retint safely here.
                    material.diffuse.contents = uniform.facemask ?? Self.facemaskGray
                case "HELMETDECAL":
                    if !uniform.abbreviation.isEmpty {
                        material.diffuse.contents = Self.abbreviationTexture(
                            uniform.abbreviation, darkText: Self.isLightColor(uniform.helmet))
                    }
                default: break
                }
            }
        }
        // Torso number decals contrast against the jersey — re-render them
        // when the jersey shade flips (node name carries the number).
        if let name = node.name, name.hasPrefix("player_"),
           let number = Int(name.dropFirst("player_".count)) {
            updateNumberDecals(on: node, number: number, jersey: uniform.jersey)
        }
    }

    /// Sleeve stripe reads against the jersey: white on a colored home
    /// jersey, team color on the white road jersey.
    private static func stripeColor(for uniform: Uniform) -> UIColor {
        isLightColor(uniform.jersey) ? uniform.accent : UIColor(white: 0.95, alpha: 1)
    }

    /// Socks read against the pants: team color over white home pants,
    /// white over team-colored road pants.
    private static func sockColor(for uniform: Uniform) -> UIColor {
        isLightColor(uniform.pants) ? uniform.accent : UIColor(white: 0.92, alpha: 1)
    }

    /// The default gray cage (kit MASK material color).
    private static let facemaskGray = UIColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1)

    /// Places 11 home and 11 away players at specified positions with jersey numbers.
    /// Coordinates are in yards from center of field. `bodyTypesHome/Away`
    /// carry the per-team-index position builds (missing index = medium).
    func positionPlayers(home: [(x: Float, z: Float, number: Int)],
                         away: [(x: Float, z: Float, number: Int)],
                         bodyTypesHome: [Int: BodyType] = [:],
                         bodyTypesAway: [Int: BodyType] = [:]) {
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

        for (index, info) in home.enumerated() {
            let node = makePlayerNode(uniform: homeUniform, number: info.number,
                                      bodyType: bodyTypesHome[index] ?? .medium)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            node.eulerAngles = SCNVector3(0, homeYaw, 0)
            rootNode.addChildNode(node)
            homePlayerNodes.append(node)
            startIdle(on: node, seed: index)
        }

        for (index, info) in away.enumerated() {
            let node = makePlayerNode(uniform: awayUniform, number: info.number,
                                      bodyType: bodyTypesAway[index] ?? .medium)
            node.position = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            node.eulerAngles = SCNVector3(0, awayYaw, 0)
            rootNode.addChildNode(node)
            awayPlayerNodes.append(node)
            startIdle(on: node, seed: index + 11)
        }
    }

    // MARK: - Idle Micro-Motion

    /// A permanent, tiny breath/weight-shift loop on the torso so nobody ever
    /// stands statue-still: the body bobs ~2 cm and rocks a hair, with phase
    /// and tempo staggered deterministically per figure. It runs on the
    /// "body" child under its own key, composing with every other animation
    /// (gait bob and stance both drive the figure node, the run twist is an
    /// absolute rotate the relative sway rides on), so it never needs to be
    /// paused — one repeatForever action per figure, no per-frame work.
    private func startIdle(on node: SCNNode, seed: Int) {
        guard let figure = node.childNode(withName: "figure", recursively: false),
              let body = figure.childNode(withName: "body", recursively: false) else { return }
        body.removeAction(forKey: "idle")
        // Re-anchor the loop from the torso's rest pose so repeated resets
        // can't accumulate a drift offset.
        body.position = SCNVector3(0, 0.42, 0)

        let period = 2.0 + Self.hash01(seed * 17 + 3) * 1.4          // 2.0-3.4 s
        let phase = Self.hash01(seed * 29 + 7) * period              // staggered start
        let breathe = SCNAction.moveBy(x: 0, y: 0.022, z: 0, duration: period / 2)
        breathe.timingMode = .easeInEaseOut
        let sway = SCNAction.rotateBy(x: 0.02, y: 0, z: 0.012, duration: period / 2)
        sway.timingMode = .easeInEaseOut
        let cycle = SCNAction.sequence([
            SCNAction.group([breathe, sway]),
            SCNAction.group([breathe.reversed(), sway.reversed()]),
        ])
        body.runAction(SCNAction.sequence([
            SCNAction.wait(duration: phase),
            SCNAction.repeatForever(cycle),
        ]), forKey: "idle")
    }

    // MARK: - Bystander Sweep (#29)

    /// Sweep counter — feeds the deterministic hash so each player's fidget
    /// beats land on different ticks instead of the whole field twitching
    /// in sync.
    private var idleSweepCounter = 0

    /// Every ~0.7 s a cheap sweep visits all 22 players: whoever is standing
    /// with no active move/gait/gesture gets (a) a slow, clamped upper-body
    /// turn that follows the live ball and (b) an occasional weight-shift +
    /// helmet-glance fidget. The torso breath loop (`startIdle`) covers the
    /// sub-2 cm scale; this covers the visible scale — bystanders outside
    /// the action track the play instead of standing statue-still.
    ///
    /// Pure scheduled SCNActions, no per-frame work. Every effect is either
    /// naturally overwritten by the next absolute gait/stance/fall rotation
    /// or cleared via `clearBystanderIdle` where those actions start, so it
    /// never fights an active animation.
    private func startIdleSweep() {
        rootNode.removeAction(forKey: "idleSweep")
        let tick = SCNAction.sequence([
            SCNAction.wait(duration: 0.7),
            SCNAction.run({ [weak self] _ in self?.idleSweepTick() }, queue: .main),
        ])
        rootNode.runAction(SCNAction.repeatForever(tick), forKey: "idleSweep")
    }

    private func idleSweepTick() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        idleSweepCounter &+= 1
        let ball = ballNode.presentation.worldPosition
        for (index, node) in (homePlayerNodes + awayPlayerNodes).enumerated() {
            guard let figure = node.childNode(withName: "figure", recursively: false),
                  isBystander(node, figure: figure) else { continue }

            // (b) Watch the ball: a slow figure yaw toward the live ball,
            // clamped to a natural half-turn and only when the ball is
            // roughly in the front hemisphere — a huddled man whose back is
            // to the spot doesn't corkscrew after it.
            let dx = ball.x - node.position.x
            let dz = ball.z - node.position.z
            let distance = (dx * dx + dz * dz).squareRoot()
            if distance > 4 {
                var delta = atan2(dx, dz) - node.eulerAngles.y
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                // Only a small glance, and only when the ball is already close to
                // straight ahead. A wider turn made wide players (esp. offense
                // receivers) square up to the ball at the center instead of
                // holding their assignment down the field — which read as facing
                // the wrong way.
                if abs(delta) < 0.8 {
                    let target = max(-0.2, min(0.2, delta))
                    let turn = target - figure.eulerAngles.y
                    if abs(turn) > 0.12 {
                        let watch = SCNAction.rotateBy(x: 0, y: CGFloat(turn), z: 0,
                                                       duration: 0.6)
                        watch.timingMode = .easeInEaseOut
                        figure.runAction(watch, forKey: "watch")
                    }
                }
            }

            // (a) Weight shift + helmet glance: ~55 % of quiescent players
            // fidget each sweep, on per-player staggered ticks. The sway has
            // to survive the coach camera: a hip shift of ~8 cm with a light
            // counter-roll reads as a man rocking foot-to-foot; anything
            // smaller is sub-pixel at this distance (measured via
            // motion_profile) and the field still reads frozen.
            let roll = Self.hash01(index * 31 + idleSweepCounter * 7 + 11)
            guard roll < 0.55 else { continue }
            let side: CGFloat = roll < 0.275 ? 1 : -1
            let sway = SCNAction.group([
                SCNAction.moveBy(x: side * 0.08, y: 0, z: 0, duration: 0.6),
                SCNAction.rotateBy(x: 0, y: 0, z: side * -0.05, duration: 0.6),
            ])
            sway.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([sway, sway.reversed()]), forKey: "fidget")
            if let helmet = figure.childNode(withName: "helmet", recursively: false) {
                let glance = SCNAction.rotateBy(x: 0, y: side * 0.3, z: 0, duration: 0.45)
                glance.timingMode = .easeInEaseOut
                helmet.runAction(SCNAction.sequence([
                    glance, SCNAction.wait(duration: 0.35), glance.reversed(),
                ]), forKey: "fidget")
            }
        }
    }

    /// True when nothing else is animating the man: no container move or
    /// facing turn, no gait/gesture on the figure, no arm gesture mid-swing,
    /// and he is upright-ish — a downed man in the pile and a lineman locked
    /// into his three-point stance both hold their pose (pre-snap stillness
    /// on the line is correct football).
    private func isBystander(_ node: SCNNode, figure: SCNNode) -> Bool {
        for key in ["playMove", "formationMove", "walk", "facing", "settleFacing", "pitchTurn"]
        where node.action(forKey: key) != nil { return false }
        for key in ["gait", "stance", "fall", "hop", "shove", "spinMove", "watch", "fidget"]
        where figure.action(forKey: key) != nil { return false }
        if abs(figure.eulerAngles.x) > 0.45 || abs(figure.eulerAngles.z) > 0.45 { return false }
        if let body = figure.childNode(withName: "body", recursively: false),
           body.action(forKey: "twist") != nil { return false }
        for name in ["arm", "armR"] {
            if let arm = figure.childNode(withName: name, recursively: false),
               arm.action(forKey: "swing") != nil { return false }
        }
        return true
    }

    /// Kills any in-flight bystander idle the moment a real animation claims
    /// the figure, so the watch/fidget rotations never fight a gait, stance,
    /// fall or block. The absolute rotations those actions run also wipe the
    /// tiny relative offsets a cut loop could leave behind.
    private func clearBystanderIdle(_ figure: SCNNode) {
        figure.removeAction(forKey: "watch")
        figure.removeAction(forKey: "fidget")
        figure.childNode(withName: "helmet", recursively: false)?
            .removeAction(forKey: "fidget")
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
        /// QB under center: bent at the waist, both hands extended down under
        /// the C's rear waiting on the exchange.
        case underCenter
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
                                stancesAway: [Int: Stance] = [:],
                                bodyTypesHome: [Int: BodyType] = [:],
                                bodyTypesAway: [Int: BodyType] = [:]) {
        guard homePlayerNodes.count == home.count,
              awayPlayerNodes.count == away.count,
              !home.isEmpty || !away.isEmpty else {
            positionPlayers(home: home, away: away,
                            bodyTypesHome: bodyTypesHome, bodyTypesAway: bodyTypesAway)
            return
        }

        // Once set, each side squares up toward the other across the LOS.
        let homeAvgZ = home.map(\.z).reduce(0, +) / Float(max(home.count, 1))
        let awayAvgZ = away.map(\.z).reduce(0, +) / Float(max(away.count, 1))
        let homeYaw: Float = awayAvgZ >= homeAvgZ ? 0 : .pi
        let awayYaw: Float = homeYaw == 0 ? .pi : 0

        let generation = playGeneration
        for (offset, pair) in zip(homePlayerNodes + awayPlayerNodes, home + away).enumerated() {
            let (node, info) = pair
            let target = SCNVector3(info.x, FieldConstants.playerHeight / 2, info.z)
            updateJerseyNumber(on: node, to: info.number)

            let isHomeNode = offset < homePlayerNodes.count
            let settleYaw = isHomeNode ? homeYaw : awayYaw
            let stance = isHomeNode
                ? (stancesHome[offset] ?? .upright)
                : (stancesAway[offset - homePlayerNodes.count] ?? .upright)

            // Restamp the position build: the same node flips between
            // offense and defense roles on possession changes. An empty
            // dict (kick formations) leaves the previous builds alone.
            let bodyTypes = isHomeNode ? bodyTypesHome : bodyTypesAway
            if !bodyTypes.isEmpty {
                let teamIndex = isHomeNode ? offset : offset - homePlayerNodes.count
                applyBodyType(bodyTypes[teamIndex] ?? .medium, to: node)
            }

            let start = { [weak self, weak node] in
                guard let self, let node, self.playGeneration == generation else { return }
                self.run(node: node, to: target, duration: duration, key: "formationMove")
                let settle = SCNAction.sequence([
                    SCNAction.wait(duration: duration),
                    SCNAction.rotateTo(x: 0, y: CGFloat(settleYaw), z: 0, duration: 0.25,
                                       usesShortestUnitArc: true),
                ])
                node.runAction(settle, forKey: "settleFacing")
                // Everyone drops into his stance once he arrives at the line
                // (upright is applied too — it resets any previous stance).
                self.applyStance(stance, to: node, delay: duration + 0.2)
            }

            // Staggered break to the line: 0-0.4 s per man, deterministic by
            // slot, so the formation never assembles in lockstep. Teleport
            // syncs (duration ≤ 0.3) keep the old instant behavior.
            let stagger = duration > 0.3 ? Self.hash01(offset * 13 + 5) * 0.4 : 0
            if stagger < 0.02 {
                start()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + stagger, execute: start)
            }
        }
    }

    /// Cheap deterministic 0…1 hash for per-player stagger/idle variation.
    private static func hash01(_ seed: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 0x9E37)
        x ^= x >> 13
        x = x &* 0x9E3779B97F4A7C15
        x ^= x >> 31
        return Double(x % 1024) / 1023.0
    }

    /// Gathers one side's 11 players into a huddle ring at the given spots
    /// (ring-shaped, from `PlayChoreographer.huddlePositions`); each man
    /// turns in toward the ring's center once he arrives. The next
    /// `movePlayersToFormation` breaks the huddle to the line.
    func huddle(teamIsHome: Bool, positions: [(x: Float, z: Float)],
                duration: TimeInterval = 0.55) {
        let nodes = teamIsHome ? homePlayerNodes : awayPlayerNodes
        guard nodes.count == positions.count, !positions.isEmpty else { return }
        let centerX = positions.map(\.x).reduce(0, +) / Float(positions.count)
        let centerZ = positions.map(\.z).reduce(0, +) / Float(positions.count)
        let generation = playGeneration
        for (offset, pair) in zip(nodes, positions).enumerated() {
            let (node, spot) = pair
            let start = { [weak self, weak node] in
                guard let self, let node, self.playGeneration == generation else { return }
                self.run(node: node, to: SCNVector3(spot.x, FieldConstants.playerHeight / 2, spot.z),
                         duration: duration, key: "formationMove")
                let yaw = atan2(centerX - spot.x, centerZ - spot.z)
                node.runAction(SCNAction.sequence([
                    SCNAction.wait(duration: duration),
                    SCNAction.rotateTo(x: 0, y: CGFloat(yaw), z: 0, duration: 0.22,
                                       usesShortestUnitArc: true),
                ]), forKey: "settleFacing")
            }
            // A ragged 0-0.25 s trickle into the ring — no synchronized rush.
            let stagger = Self.hash01(offset * 7 + 11) * 0.25
            if stagger < 0.02 {
                start()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + stagger, execute: start)
            }
        }
    }

    /// Eases a figure into `stance` after `delay` (the formation travel time).
    /// Limb poses run under the same "swing"/"bend" keys the run cycle uses,
    /// so the next `swingLimbs` at the snap replaces them seamlessly; the
    /// figure pitch/sink runs under "stance", which `run` clears on takeoff.
    private func applyStance(_ stance: Stance, to node: SCNNode, delay: TimeInterval) {
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        clearBystanderIdle(figure)

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
        case .underCenter:
            // Bent forward, knees soft, both hands reaching down-forward
            // under the center for the exchange.
            pitch = 0.42; sink = -0.09
            limbs = [
                ("arm", -0.8, 0.15, -0.25),
                ("armR", -0.8, -0.15, -0.25),
                ("leg", 0.25, 0, -0.35),
                ("legR", 0.25, 0, -0.35),
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
    /// the camera creeps toward the LOS over 2.5 s (~2 yards in broadcast,
    /// a barely-there half yard in the already-tight coach shot). Any new
    /// focus, kick camera, or the snap itself (`runPlay`) interrupts the
    /// dolly, and the next absolute focus move corrects the offset.
    ///
    /// `style` overrides the user's `cameraStyle` for this shot (kickoffs
    /// keep the wide broadcast frame even in coach mode); follow-cam pans
    /// during the play inherit the override via `currentShotStyle`.
    /// The camera rig for one shot style: where the aim point and the lens
    /// body sit relative to the framing z. Shared by the scripted
    /// `focusCamera` moves and the per-frame live follow, so the follow
    /// keeps the exact scripted framing while it glides.
    private struct ShotRig {
        /// Aim point height and its z-lead (in +viewFacing yards).
        let targetHeight: Float
        let targetLead: Float
        /// Camera height and how far it sits behind the framing z
        /// (in -viewFacing yards).
        let cameraHeight: Float
        let cameraBack: Float
    }

    /// Rig numbers per style/framing.
    ///
    /// Coach: elevated behind the offense — R-camera-fix pulled the shot
    /// ~14 % further out along its own aim ray (was 8.2 up / 18.6 back per
    /// the previous 10 % pull): the backfield QB now reads ~11-12 % of the
    /// viewport height (was ~13-14 %), so a deep catch + YAC fits in frame
    /// while the follow rig glides. Defense keeps the same pull on its
    /// raised variant so routes read over the OL.
    private func shotRig(for style: CameraStyle) -> ShotRig {
        switch style {
        case .coach:
            return defensiveFraming
                ? ShotRig(targetHeight: 1.0, targetLead: 3, cameraHeight: 10.5, cameraBack: 21.5)
                : ShotRig(targetHeight: 1.0, targetLead: 4, cameraHeight: 9.2, cameraBack: 21.8)
        case .broadcast:
            return defensiveFraming
                ? ShotRig(targetHeight: 0.5, targetLead: -7, cameraHeight: 33, cameraBack: 39)
                : ShotRig(targetHeight: 1.5, targetLead: 19, cameraHeight: 24, cameraBack: 29)
        }
    }

    func focusCamera(z: Float, animated: Bool = true, duration: TimeInterval = 0.8,
                     pushIn: Bool = false, style styleOverride: CameraStyle? = nil) {
        // A running replay owns the shot outright — scripted refocuses (and
        // the follow-cam) resume once endReplayCamera() hands it back.
        guard !replayCameraActive else { return }
        kickCameraActive = false
        cameraNode.removeAction(forKey: "pushIn")
        let clampedZ = max(-45, min(45, z))
        focusZ = clampedZ
        let style = styleOverride ?? cameraStyle
        let shotStyleChanged = style != currentShotStyle
        currentShotStyle = style
        // The precipitation is tuned per shot style (the low coach lens sits
        // inside the spawn slab) — swap the emitter when the framing flips.
        if shotStyleChanged { retuneWeatherEmitter() }

        // Mid-play style toggle: the live follow rig reads the new style's
        // offsets every frame and glides the shot over — scripted actions
        // would only fight the per-frame constraints.
        if liveFollowActive { return }

        // The camera always sits behind the player's own unit, mirrored via
        // `viewFacing` for away games; defense swaps to its own variant so
        // the play develops INTO the frame instead of behind it.
        let rig = shotRig(for: style)
        let targetPosition = SCNVector3(0, rig.targetHeight, clampedZ + viewFacing * rig.targetLead)
        let cameraPosition = SCNVector3(0, rig.cameraHeight, clampedZ - viewFacing * rig.cameraBack)
        let fieldOfView: CGFloat = 52

        // Lens change rides the same ease as the move (zNear stays at 1;
        // the closest coach-shot player is still ~10 yd from the camera).
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.camera?.fieldOfView = fieldOfView
        SCNTransaction.commit()

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
        moveWeatherEmitter(toZ: clampedZ, animated: animated, duration: duration)

        if pushIn && animated {
            // Slow dolly along the (horizontal) view direction toward the LOS.
            // The coach shot is calibrated so the whole box fits, so its dolly
            // is a whisper (0.5 yd, no drop) — just enough life in the frame.
            let dx = targetPosition.x - cameraPosition.x
            let dz = targetPosition.z - cameraPosition.z
            let length = sqrt(dx * dx + dz * dz)
            guard length > 0.1 else { return }
            let scale = (style == .coach ? 0.5 : 2.0) / length
            let dolly = SCNAction.moveBy(x: CGFloat(dx * scale),
                                         y: style == .coach ? 0 : -0.4,
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
        endLiveFollow()
        kickCameraActive = true
        cameraNode.removeAction(forKey: "pushIn")
        // The behind-the-posts shot is framed for the broadcast lens — undo
        // the coach shot's long lens for the duration of the kick.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.camera?.fieldOfView = 52
        SCNTransaction.commit()
        let sign: Float = towardZ >= 0 ? 1 : -1
        let cameraPosition = SCNVector3(0, 8, sign * 72)
        let targetPosition = SCNVector3(0, 4, sign * 40)

        let targetMove = SCNAction.move(to: targetPosition, duration: duration)
        targetMove.timingMode = .easeInEaseOut
        cameraTargetNode.runAction(targetMove, forKey: "focus")

        let cameraMove = SCNAction.move(to: cameraPosition, duration: duration)
        cameraMove.timingMode = .easeInEaseOut
        cameraNode.runAction(cameraMove, forKey: "focus")

        // Keep the precipitation slab a step downfield of the low kick
        // camera so streaks/flakes never cross right in front of the lens.
        // The slab center is explicit here — no coach-mode offset on top.
        moveWeatherEmitter(toZ: sign * 30, animated: true, duration: duration, applyOffset: false)
    }

    /// Post-tackle beat for the tight coach shot: eases the camera ~30 %
    /// further out along its aim ray (which also lifts it ~30 %) so the pile
    /// reads before the next formation forms up. The next `focusCamera`
    /// (pre-snap sync) moves to absolute coordinates and undoes the offset.
    /// No-op in broadcast framing (already wide) and while a kick shot or a
    /// scoring refocus owns the camera.
    func pullBackAfterPlay(duration: TimeInterval = 1.0) {
        guard currentShotStyle == .coach, !kickCameraActive, !replayCameraActive else { return }
        cameraNode.removeAction(forKey: "pushIn")
        let cam = cameraNode.position
        let aim = cameraTargetNode.position
        let pulled = SCNVector3(aim.x + (cam.x - aim.x) * 1.3,
                                aim.y + (cam.y - aim.y) * 1.3,
                                aim.z + (cam.z - aim.z) * 1.3)
        let move = SCNAction.move(to: pulled, duration: duration)
        move.timingMode = .easeInEaseOut
        // Same action key as the focus move so the next focus replaces it.
        cameraNode.runAction(move, forKey: "focus")
    }

    // MARK: - Live follow rig

    /// Installs the per-frame live follow: the aim point eases onto the ball
    /// every rendered frame and the camera trails it at the current style's
    /// exact rig offset — one continuous glide instead of stepwise pans, in
    /// both framings and at any playback speed. `runPlay` starts it at the
    /// snap; kicks and replays keep their own shots (guarded here).
    private func beginLiveFollow() {
        guard !kickCameraActive, !replayCameraActive, !liveFollowActive else { return }
        liveFollowActive = true
        followAnchorZ = focusZ
        followProgress = 0
        cameraNode.removeAction(forKey: "pushIn")
        cameraNode.removeAction(forKey: "focus")
        cameraTargetNode.removeAction(forKey: "focus")

        let aim = SCNTransformConstraint.positionConstraint(inWorldSpace: true) {
            [weak self] _, position in
            guard let self, self.liveFollowActive else { return position }
            let rig = self.shotRig(for: self.currentShotStyle)
            let baseZ = self.followBaseZ()
            let ballX = self.ballNode.presentation.worldPosition.x
            let goal = SCNVector3(max(-14, min(14, ballX * 0.85)),
                                  rig.targetHeight,
                                  baseZ + self.viewFacing * rig.targetLead)
            return SCNVector3(position.x + (goal.x - position.x) * 0.12,
                              position.y + (goal.y - position.y) * 0.12,
                              position.z + (goal.z - position.z) * 0.12)
        }
        cameraTargetNode.constraints = [aim]

        let chase = SCNTransformConstraint.positionConstraint(inWorldSpace: true) {
            [weak self] _, position in
            guard let self, self.liveFollowActive else { return position }
            let rig = self.shotRig(for: self.currentShotStyle)
            let baseZ = self.followBaseZ()
            let ballX = self.ballNode.presentation.worldPosition.x
            let goal = SCNVector3(max(-10, min(10, ballX * 0.55)),
                                  rig.cameraHeight,
                                  baseZ - self.viewFacing * rig.cameraBack)
            return SCNVector3(position.x + (goal.x - position.x) * 0.10,
                              position.y + (goal.y - position.y) * 0.10,
                              position.z + (goal.z - position.z) * 0.10)
        }
        if let lookAt = cameraLookAtConstraint {
            cameraNode.constraints = [chase, lookAt]
        } else {
            cameraNode.constraints = [chase]
        }
    }

    /// The framing z the follow rig wants this frame. A forward ratchet with
    /// backward slack: the frame moves downfield (attack direction) with the
    /// ball immediately, but only retreats once the ball is 6+ yards behind
    /// the frame — so a QB dropback doesn't pump the composition while a
    /// return running the other way still drags the camera along. Called from
    /// the follow constraints (render thread).
    private func followBaseZ() -> Float {
        let attack: Float = defensiveFraming ? -viewFacing : viewFacing
        let ballZ = ballNode.presentation.worldPosition.z
        let progress = (ballZ - followAnchorZ) * attack
        followProgress = max(followProgress, progress)
        followProgress = min(followProgress, progress + 6)
        return max(-45, min(45, followAnchorZ + attack * followProgress))
    }

    /// Hands the shot back to the scripted focus machinery without a cut:
    /// the model transforms are frozen where the follow's presentation
    /// ended, then the plain look-at rig is restored. `focusZ` is synced to
    /// the final framing so the post-play pull-back and the next pre-snap
    /// focus start from what's on screen.
    private func endLiveFollow() {
        guard liveFollowActive else { return }
        liveFollowActive = false
        cameraTargetNode.position = cameraTargetNode.presentation.position
        cameraNode.position = cameraNode.presentation.position
        cameraTargetNode.constraints = nil
        if let lookAt = cameraLookAtConstraint {
            cameraNode.constraints = [lookAt]
        }
        let rig = shotRig(for: currentShotStyle)
        focusZ = max(-45, min(45, cameraTargetNode.position.z - viewFacing * rig.targetLead))
    }

    /// Keeps the precipitation slab riding with the live follow: each step
    /// that sends the ball somewhere eases the emitter toward that spot over
    /// the step's own duration (the per-frame rig only moves the camera).
    private func driftWeatherEmitter(for step: PlayStep) {
        guard liveFollowActive,
              let node = rootNode.childNode(withName: "weatherEmitter", recursively: false)
        else { return }
        let destZ: Float?
        switch step.ballMove {
        case .arc(let to, _, _, _): destZ = to.z
        case .slide(let to, _): destZ = to.z
        case .carry(let index), .carryChest(let index):
            destZ = step.moves.first { $0.nodeIndex == index }?.to.z
                ?? step.paths.first { $0.nodeIndex == index }?.points.last?.z
        case .snap, nil:
            destZ = nil
        }
        guard let destZ else { return }
        let goalZ = max(-45, min(45, destZ)) + weatherSlabZOffset
        guard abs(goalZ - node.position.z) > 6 else { return }
        let move = SCNAction.move(to: SCNVector3(0, Self.weatherEmitterHeight, goalZ),
                                  duration: max(effectiveDuration(of: step), 0.4))
        move.timingMode = .easeInEaseOut
        node.runAction(move, forKey: "focus")
    }

    // MARK: - Replay Camera (R35)

    /// Camera angles for the instant-replay presentation. The choreography
    /// steps are deterministic, so a replay is just the same timeline run
    /// again — these shots make it read as NEW footage: per-frame follower
    /// constraints ease the aim point onto the ball (or an isolated
    /// defender), replay-truck style, instead of the scripted focus pans.
    enum ReplayAngle: Equatable {
        /// Low shot from the near rail that slides along the field with the
        /// ball — the classic sideline replay angle.
        case sideline
        /// Parked low behind the end zone the offense attacks — touchdowns
        /// fly straight at the lens.
        case endZone
        /// Isolation on the defense's key man of the play (matchup
        /// winner/loser): the camera trails him from behind the defense so
        /// his read-and-react tells the story of the snap.
        case isolateDefense(nodeIndex: Int)
    }

    /// While true the replay presentation owns the shot: `focusCamera` (and
    /// with it the in-play follow-cam and every scripted refocus) stands
    /// down until `endReplayCamera()` hands the field back.
    private(set) var replayCameraActive = false

    /// Installs the replay shot: parks the camera at the angle's vantage
    /// point and swaps in per-frame constraints that chase the story —
    /// the camera target eases onto the ball/defender every rendered frame
    /// (trailing smoothing, no hard cuts mid-play), and the sideline/iso
    /// bodies slide to keep the action in frame. Call again mid-replay to
    /// cut to a different angle; the constraints simply reinstall.
    func beginReplayCamera(angle: ReplayAngle, losZ: Float, direction: Float) {
        endLiveFollow()
        replayCameraActive = true
        kickCameraActive = false
        cameraNode.removeAction(forKey: "pushIn")
        cameraNode.removeAction(forKey: "focus")
        cameraTargetNode.removeAction(forKey: "focus")

        // Slight tele from the rail; the end zone keeps a normal lens so the
        // whole goal-line picture fits.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.3
        cameraNode.camera?.fieldOfView = angle == .endZone ? 50 : 44
        SCNTransaction.commit()

        // What the shot follows: the ball, or the isolated defender.
        let storyPoint: () -> SCNVector3?
        switch angle {
        case .sideline, .endZone:
            storyPoint = { [weak self] in self?.ballNode.presentation.worldPosition }
        case .isolateDefense(let index):
            storyPoint = { [weak self] in self?.playerNode(at: index)?.presentation.worldPosition }
        }
        let aim = SCNTransformConstraint.positionConstraint(inWorldSpace: true) { _, position in
            guard let goal = storyPoint() else { return position }
            return SCNVector3(position.x + (goal.x - position.x) * 0.14,
                              position.y + (goal.y + 0.3 - position.y) * 0.14,
                              position.z + (goal.z - position.z) * 0.14)
        }
        cameraTargetNode.constraints = [aim]
        cameraTargetNode.position = SCNVector3(0, 0.9, losZ)

        guard let lookAt = cameraLookAtConstraint else { return }
        switch angle {
        case .sideline:
            // Near rail, low, level with the LOS; the body slides along Z
            // with the ball while X/Y stay parked (the bump can still dip Y).
            cameraNode.position = SCNVector3(-27.5, 3.2, max(-58, min(58, losZ)))
            let slide = SCNTransformConstraint.positionConstraint(inWorldSpace: true) {
                [weak self] _, position in
                guard let self else { return position }
                let ballZ = max(-58, min(58, self.ballNode.presentation.worldPosition.z))
                return SCNVector3(position.x, position.y,
                                  position.z + (ballZ - position.z) * 0.08)
            }
            cameraNode.constraints = [slide, lookAt]
        case .endZone:
            // Behind the goal line the offense attacks, looking back upfield.
            cameraNode.position = SCNVector3(0, 5.0, direction * 63)
            cameraNode.constraints = [lookAt]
        case .isolateDefense(let index):
            let man = playerNode(at: index)?.presentation.worldPosition
                ?? SCNVector3(0, 1, losZ + direction * 8)
            cameraNode.position = SCNVector3(man.x * 0.7, 3.6,
                                             max(-58, min(58, man.z + direction * 12)))
            let trail = SCNTransformConstraint.positionConstraint(inWorldSpace: true) {
                [weak self] _, position in
                guard let self, let spot = self.playerNode(at: index)?.presentation.worldPosition
                else { return position }
                let goalX = max(-24, min(24, spot.x * 0.7))
                let goalZ = max(-58, min(58, spot.z + direction * 12))
                return SCNVector3(position.x + (goalX - position.x) * 0.07,
                                  position.y,
                                  position.z + (goalZ - position.z) * 0.07)
            }
            cameraNode.constraints = [trail, lookAt]
        }
    }

    /// Removes the replay follower constraints and hands the camera back to
    /// the normal focus machinery. The caller refocuses (`focusCamera` /
    /// pre-snap sync) — this only restores the plain look-at rig.
    func endReplayCamera() {
        guard replayCameraActive else { return }
        replayCameraActive = false
        cameraTargetNode.constraints = nil
        if let lookAt = cameraLookAtConstraint {
            cameraNode.constraints = [lookAt]
        }
    }

    /// Playback rate for play timelines (the HUD's 1x/2x button): 2 halves
    /// every step/move/ball duration at schedule time — pure presentation,
    /// the sim result and the game clock are untouched.
    var playbackSpeed: Double = 1

    /// The clamped rate the running timeline is scaled by. The snap flight
    /// and its carry-attach ride this same clock so the carry is always
    /// assigned before the following throw fires.
    private var currentPlaybackRate: Double = 1

    /// One step re-timed by a duration factor (playback speed).
    private func scaledStep(_ step: PlayStep, by factor: Double) -> PlayStep {
        var out = step
        out.duration = step.duration * factor
        out.moves = step.moves.map { ($0.nodeIndex, $0.to, $0.duration * factor) }
        out.paths = step.paths.map { ($0.nodeIndex, $0.points, $0.duration * factor) }
        out.startDelays = step.startDelays.mapValues { $0 * factor }
        out.openField = step.openField.map {
            OpenFieldMove(nodeIndex: $0.nodeIndex, kind: $0.kind, delay: $0.delay * factor)
        }
        switch step.ballMove {
        case .arc(let to, let apex, let duration, let from):
            out.ballMove = .arc(to: to, apex: apex, duration: duration * factor, from: from)
        case .slide(let to, let duration):
            out.ballMove = .slide(to: to, duration: duration * factor)
        default:
            break
        }
        return out
    }

    /// Runs a sequential play timeline: each step starts after the previous one
    /// finishes; within a step all moves (and the ball behavior) start together.
    /// `completion` fires on the main queue after the last step ends.
    ///
    /// When the timeline ends, everyone still on his feet gets a short
    /// decelerating follow-through slide (no hard freeze at the whistle), and
    /// a beat later the field starts a slow walk toward the ball — the
    /// between-plays wait reads as players regrouping, not statues. Both die
    /// with the play generation as soon as anything else claims the field.
    func runPlay(steps: [PlayStep], completion: @escaping () -> Void) {
        cancelPlay()
        // The snap kills the pre-snap push-in; the follow-cam owns the shot now.
        cameraNode.removeAction(forKey: "pushIn")
        beginLiveFollow()
        pendingCatchNodes = []
        let generation = playGeneration

        let rate = min(max(playbackSpeed, 0.5), 4)
        currentPlaybackRate = rate
        let timed = rate == 1 ? steps : steps.map { scaledStep($0, by: 1 / rate) }

        var startTime: TimeInterval = 0
        for step in timed {
            DispatchQueue.main.asyncAfter(deadline: .now() + startTime) { [weak self] in
                guard let self = self, self.playGeneration == generation else { return }
                self.execute(step: step)
            }
            startTime += effectiveDuration(of: step)
        }

        // Whoever was in motion over the final beats keeps sliding to a stop.
        let lastMovers = Set(timed.suffix(2).flatMap { step in
            step.moves.map(\.nodeIndex) + step.paths.map(\.nodeIndex)
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + startTime) { [weak self] in
            guard let self = self, self.playGeneration == generation else { return }
            self.followThrough(nodeIndexes: lastMovers)
            self.detachBallToRoot()
            self.endLiveFollow()
            completion()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self = self, self.playGeneration == generation else { return }
                self.postPlayWalk()
            }
        }
    }

    /// Post-whistle momentum: each node that was still moving when the play
    /// ended drifts 0.4-0.8 s further along its facing, easing out — players
    /// decelerate through the whistle instead of stopping dead. Fallen men
    /// stay in the pile.
    private func followThrough(nodeIndexes: Set<Int>) {
        for index in nodeIndexes {
            guard let node = playerNode(at: index),
                  let figure = node.childNode(withName: "figure", recursively: false),
                  figure.action(forKey: "fall") == nil else { continue }
            let yaw = node.eulerAngles.y
            let reach = Float.random(in: 0.6...1.1)
            let duration = TimeInterval.random(in: 0.4...0.8)
            let drift = SCNAction.moveBy(x: CGFloat(sin(yaw) * reach), y: 0,
                                         z: CGFloat(cos(yaw) * reach), duration: duration)
            drift.timingMode = .easeOut
            node.runAction(drift, forKey: "walk")
        }
    }

    /// Between plays everyone on his feet walks slowly toward (a ring around)
    /// the dead ball — deterministic per-man ring spots keep them separated,
    /// and the walk is capped at a few yards so a 50-yard punt doesn't march
    /// the line downfield. Any formation move / snap replaces the walk (see
    /// the cross-key cleanup in `run`).
    private func postPlayWalk() {
        let ball = ballNode.worldPosition
        for (index, node) in (homePlayerNodes + awayPlayerNodes).enumerated() {
            guard let figure = node.childNode(withName: "figure", recursively: false),
                  figure.action(forKey: "fall") == nil,
                  node.action(forKey: "playMove") == nil,
                  node.action(forKey: "formationMove") == nil else { continue }
            // A deterministic ring spot per node: staggered angles + radii.
            let angle = Float(index) / 22 * 2 * .pi + 0.45
            let radius = 2.4 + Float(index % 5) * 0.8
            let targetX = min(max(ball.x + sin(angle) * radius, -25), 25)
            let targetZ = min(max(ball.z + cos(angle) * radius, -56), 56)
            let dx = targetX - node.position.x
            let dz = targetZ - node.position.z
            let distance = (dx * dx + dz * dz).squareRoot()
            guard distance > 1.4 else { continue }
            let capped = min(distance, 4.5)
            let to = SCNVector3(node.position.x + dx / distance * capped,
                                node.position.y,
                                node.position.z + dz / distance * capped)
            // Walk pace ~1.6 yd/s — `run` drops into the low-speed walk gait.
            run(node: node, to: to, duration: TimeInterval(capped / 1.6), key: "walk")
        }
    }

    /// Stops a running play: pending steps are dropped, running actions removed,
    /// and the ball is detached back to the root node at its current world position.
    func cancelPlay() {
        playGeneration += 1
        endLiveFollow()
        for node in homePlayerNodes + awayPlayerNodes {
            node.removeAction(forKey: "playMove")
            node.removeAction(forKey: "walk")
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
        // R38 Reduce Motion: the highlight stays informative but swaps the
        // scale pop for a brief opacity dip (no size/position change).
        if UIAccessibility.isReduceMotionEnabled {
            let dim = SCNAction.fadeOpacity(to: 0.55, duration: 0.15)
            let restore = SCNAction.fadeOpacity(to: 1.0, duration: 0.15)
            node.runAction(SCNAction.sequence([dim, restore]), forKey: "pulse")
            return
        }
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
    /// markers. Pass nil to hide either. `offenseDirection` (+1 = offense
    /// drives toward +Z) walks the referee to his spot behind the play; when
    /// omitted it is inferred from the first-down stripe or the last known
    /// direction (kicks pass nil for everything and the ref stays put).
    func updateMarkers(losZ: Float?, firstDownZ: Float?, offenseDirection: Float? = nil) {
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
        if let losZ {
            if let offenseDirection {
                refereeDirection = offenseDirection >= 0 ? 1 : -1
            } else if let firstDownZ {
                refereeDirection = firstDownZ >= losZ ? 1 : -1
            }
            moveReferee(losZ: max(-50, min(50, losZ)), direction: refereeDirection)
        }
    }

    // MARK: - Play Execution (private)

    private func playerNode(at index: Int) -> SCNNode? {
        let allPlayers = homePlayerNodes + awayPlayerNodes
        guard index >= 0, index < allPlayers.count else { return nil }
        return allPlayers[index]
    }

    /// One full leg cycle for a runner at `speed` yards/second — faster feet
    /// as the player moves faster; backpedals chop at a fixed cadence, and
    /// sub-3 yd/s paces drop into a leisurely walking cadence.
    private func strideTime(forSpeed speed: Float, backpedal: Bool) -> TimeInterval {
        if backpedal { return 0.3 }
        if speed < 3 { return 0.5 }
        return min(max(0.38 - TimeInterval(speed) * 0.022, 0.16), 0.34)
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
        // One mover at a time: a snap cancels a late formation shift or the
        // post-play walk, a formation move cancels the walk, and so on —
        // concurrent move(to:) actions under different keys would fight.
        for other in ["playMove", "formationMove", "walk"] where other != key {
            node.removeAction(forKey: other)
        }
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

        // Animation Overhaul path: the container move + facing above already run.
        // Drive locomotion by skeletal clip instead of the procedural gait, and
        // return the figure to idle when this move ends.
        if let skel = skeletalDriver(for: figure) {
            skel.setMoving(true, speed: distance / Float(duration), backpedal: backpedal)
            figure.removeAction(forKey: "skelIdleReset")
            figure.runAction(.sequence([
                .wait(duration: duration),
                .run { [weak skel] _ in skel?.setMoving(false, speed: 0) },
            ]), forKey: "skelIdleReset")
            return
        }

        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "stance")  // the snap breaks the pre-snap pose
        clearBystanderIdle(figure)             // the run owns the figure now

        let speed = distance / Float(duration)
        let stride = strideTime(forSpeed: speed, backpedal: backpedal)

        // Bob synced to the leg cycle.
        let bobUp = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: stride / 2)
        bobUp.timingMode = .easeInEaseOut
        let cycles = max(Int(duration / stride), 1)
        let bob = SCNAction.repeat(SCNAction.sequence([bobUp, bobUp.reversed()]), count: cycles)
        // Rise out of any stance sink first so the bob oscillates around zero.
        let rise = SCNAction.move(to: SCNVector3Zero, duration: 0.1)

        // Forward lean scales with speed (~8-12°); backpedal sits slightly
        // back; a walking pace stays nearly upright.
        let lean: CGFloat = backpedal ? -0.1
            : (speed < 3 ? 0.05 : CGFloat(0.14 + min(speed, 9) / 9 * 0.08))
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
                   carry: carryStyle(of: node),
                   speed: speed, backpedal: backpedal)
    }

    /// Alternating limb swings for the duration of a move, ending neutral.
    /// Knees and elbows bend while running; the ball-carrier's left arm stays
    /// tucked around the ball instead of pumping (a chest carry holds BOTH
    /// arms on the ball). Cadence and amplitude scale with `speed` (yards/s),
    /// and the torso counter-rotates lightly against the legs. Backpedals
    /// chop with short, small steps.
    private func swingLimbs(of figure: SCNNode, duration: TimeInterval,
                            carry: CarryStyle = .none,
                            speed: Float = 5, backpedal: Bool = false) {
        let stride = strideTime(forSpeed: speed, backpedal: backpedal)
        let cycles = max(Int(duration / stride), 1)
        // Walking paces swing small and easy; running scales with speed.
        let swing: Float = backpedal ? 0.4
            : (speed < 3 ? 0.28 : min(0.45 + speed * 0.035, 0.8))

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

            if carry == .tucked && limb.name == "arm" {
                // Ball arm: tucked tight, no pumping.
                node.runAction(SCNAction.rotateTo(x: -0.55, y: 0, z: 0.35, duration: 0.2), forKey: "swing")
                joint?.runAction(SCNAction.rotateTo(x: -1.35, y: 0, z: 0, duration: 0.2), forKey: "bend")
                continue
            }
            if carry == .chest && (limb.name == "arm" || limb.name == "armR") {
                // Two-hand chest hold (QB in his drop): both arms curl on
                // the ball instead of pumping.
                let inward: CGFloat = limb.name == "arm" ? 0.28 : -0.28
                node.runAction(SCNAction.rotateTo(x: -1.0, y: 0, z: inward, duration: 0.2), forKey: "swing")
                joint?.runAction(SCNAction.rotateTo(x: -1.1, y: 0, z: 0, duration: 0.2), forKey: "bend")
                continue
            }
            node.runAction(swingAction(startForward: limb.forward, restZ: limb.restZ), forKey: "swing")
            joint?.runAction(bendAction(bend: limb.bend, rest: limb.jointRest), forKey: "bend")
        }
    }

    /// Runs a node through a polyline as chained `run` legs — SCNActions all
    /// the way down, no per-frame work. Each leg gets time proportional to
    /// its share of the total distance (constant speed through the cuts) and
    /// the facing/gait logic in `run` banks each turn. Scheduled legs die
    /// with the play generation, exactly like queued play steps.
    private func runPath(nodeIndex: Int, points: [SCNVector3], duration: TimeInterval,
                         backpedal: Bool = false) {
        guard let node = playerNode(at: nodeIndex), !points.isEmpty else { return }
        if points.count == 1 {
            run(node: node, to: points[0], duration: duration, key: "playMove", backpedal: backpedal)
            return
        }
        var lengths: [Float] = []
        var total: Float = 0
        var previous = node.position
        for point in points {
            let dx = point.x - previous.x
            let dz = point.z - previous.z
            let length = max((dx * dx + dz * dz).squareRoot(), 0.01)
            lengths.append(length)
            total += length
            previous = point
        }
        let generation = playGeneration
        var offset: TimeInterval = 0
        for (index, point) in points.enumerated() {
            let legDuration = duration * TimeInterval(lengths[index] / total)
            if index == 0 {
                run(node: node, to: point, duration: legDuration, key: "playMove",
                    backpedal: backpedal)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
                    guard let self, self.playGeneration == generation else { return }
                    self.run(node: node, to: point, duration: legDuration, key: "playMove",
                             backpedal: backpedal)
                }
            }
            offset += legDuration
        }
    }

    /// A momentary upper-body turn toward the ball at the catch: the torso
    /// (and with it the head and shoulders) rotates to `yaw` in the figure's
    /// local frame, holds through the grab, then releases so the next stride's
    /// swing resumes facing the run. Runs on the "twist" channel — the light
    /// counter-rotation `swingLimbs` uses — so it rides on top of the leg gait
    /// without fighting the node's movement facing; the YAC leg's next
    /// `swingLimbs` overwrites it, snapping the receiver back to his run.
    private func catchBodyTurn(_ figure: SCNNode, yaw: CGFloat, hold: TimeInterval = 0.5) {
        guard abs(yaw) > 0.05,
              let body = figure.childNode(withName: "body", recursively: false) else { return }
        body.removeAction(forKey: "twist")
        let turn = SCNAction.rotateTo(x: 0, y: yaw, z: 0, duration: 0.16, usesShortestUnitArc: true)
        turn.timingMode = .easeOut
        let back = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.22, usesShortestUnitArc: true)
        back.timingMode = .easeInEaseOut
        body.runAction(SCNAction.sequence([turn, SCNAction.wait(duration: hold), back]),
                       forKey: "twist")
    }

    /// The torso yaw a catch should turn to, in the receiver's local frame:
    /// toward the incoming ball for a hands / over-shoulder / diving grab,
    /// toward the near sideline for a toe-tap. Capped so it reads as a turn of
    /// the head and shoulders, never a full spin off the run.
    private func catchTurnYaw(nodeIndex: Int, style: CatchStyle, passer: SCNNode?) -> CGFloat {
        guard let node = playerNode(at: nodeIndex) else { return 0 }
        let pos = node.presentation.position
        let facing = CGFloat(node.presentation.eulerAngles.y)
        func yawTo(_ x: Float, _ z: Float) -> CGFloat {
            let dx = x - pos.x, dz = z - pos.z
            guard dx * dx + dz * dz > 0.05 else { return 0 }
            var t = CGFloat(atan2(dx, dz)) - facing
            while t > .pi { t -= 2 * .pi }
            while t < -.pi { t += 2 * .pi }
            return t
        }
        switch style {
        case .toeTap:
            let sideX: Float = pos.x >= 0 ? 30 : -30
            return max(-1.2, min(1.2, yawTo(sideX, pos.z)))
        case .reach:
            guard let p = passer?.presentation.position else { return 0 }
            return max(-1.3, min(1.3, yawTo(p.x, p.z)))
        case .overShoulder:
            guard let p = passer?.presentation.position else { return 0 }
            return max(-0.8, min(0.8, yawTo(p.x, p.z)))
        case .dive:
            guard let p = passer?.presentation.position else { return 0 }
            return max(-0.7, min(0.7, yawTo(p.x, p.z)))
        }
    }

    /// Both arms shoot up for a beat — catch attempts and pick attempts —
    /// with a small leap at the ball while the arms are up. `turnYaw` turns the
    /// torso toward the incoming ball at the grab (0 = stay square).
    private func reach(nodeIndex: Int, turnYaw: CGFloat = 0, arriveIn: TimeInterval = 0) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "catch", delay: max(0, arriveIn - 0.59))   // hands up as the ball lands
            return
        }
        catchBodyTurn(figure, yaw: turnYaw)
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

    /// How a figure goes to the turf.
    private enum FallStyle {
        /// The standard forward tackle collapse.
        case forward
        /// Blown backward off his feet onto his back (big hits).
        case backward
        /// A fast, flat horizontal launch forward (diving tackles/catches).
        case dive
        /// Legs cut from under him: a hard forward pitch, arms flung out to
        /// break the fall — the shoestring-tackle stumble.
        case trip
    }

    /// Deep-ball catch: both arms extend up and FORWARD along the run — the
    /// over-the-shoulder basket look — while the stride keeps going.
    private func overShoulderReach(nodeIndex: Int, turnYaw: CGFloat = 0, arriveIn: TimeInterval = 0) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "catch", delay: max(0, arriveIn - 0.59))
            return
        }
        catchBodyTurn(figure, yaw: turnYaw, hold: 0.6)
        for name in ["arm", "armR"] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            let up = SCNAction.rotateTo(x: -2.75, y: 0,
                                        z: name == "arm" ? 0.3 : -0.3, duration: 0.28)
            up.timingMode = .easeOut
            let down = SCNAction.rotateTo(x: 0, y: 0,
                                          z: name == "arm" ? 0.25 : -0.25, duration: 0.3)
            arm.runAction(SCNAction.sequence([up, SCNAction.wait(duration: 0.6), down]),
                          forKey: "swing")
            if let forearm = arm.childNode(withName: "forearm", recursively: false) {
                forearm.removeAction(forKey: "bend")
                forearm.runAction(SCNAction.rotateTo(x: -0.2, y: 0, z: 0, duration: 0.28),
                                  forKey: "bend")
            }
        }
    }

    /// Full-extension diving catch: the figure launches flat with the arms
    /// out, hits the turf with the ball, and stays stretched out until the
    /// pile forms before climbing up.
    private func divingCatch(nodeIndex: Int, turnYaw: CGFloat = 0, arriveIn: TimeInterval = 0) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "catch", delay: max(0, arriveIn - 0.59), hold: true)   // lay out + stay down
            return
        }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "hop")
        figure.removeAction(forKey: "stance")
        catchBodyTurn(figure, yaw: turnYaw, hold: 1.4)
        for name in ["arm", "armR"] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            arm.runAction(SCNAction.rotateTo(x: -1.7, y: 0,
                                             z: name == "arm" ? 0.12 : -0.12, duration: 0.16),
                          forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.16), forKey: "bend")
        }
        let launch = SCNAction.group([
            SCNAction.rotateTo(x: -1.5, y: 0, z: 0, duration: 0.2),
            SCNAction.move(to: SCNVector3(0, 0.12, 0.5), duration: 0.2),
        ])
        launch.timingMode = .easeOut
        let land = SCNAction.move(to: SCNVector3(0, -0.34, 0.8), duration: 0.15)
        land.timingMode = .easeIn
        let up = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5),
            SCNAction.move(to: SCNVector3Zero, duration: 0.5),
        ])
        up.timingMode = .easeInEaseOut
        figure.runAction(SCNAction.sequence([
            launch, land, SCNAction.wait(duration: 1.5), up,
        ]), forKey: "fall")
    }

    /// Sideline grab: the basic reach plus quick alternating toe taps —
    /// both feet down in bounds at the boundary.
    private func toeTapReach(nodeIndex: Int, turnYaw: CGFloat = 0, arriveIn: TimeInterval = 0) {
        reach(nodeIndex: nodeIndex, turnYaw: turnYaw, arriveIn: arriveIn)
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        for (offset, name) in ["leg", "legR"].enumerated() {
            guard let leg = figure.childNode(withName: name, recursively: false) else { continue }
            leg.removeAction(forKey: "swing")
            leg.runAction(SCNAction.sequence([
                SCNAction.wait(duration: 0.24 + Double(offset) * 0.13),
                SCNAction.rotateTo(x: -0.55, y: 0, z: 0, duration: 0.09),
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.09),
            ]), forKey: "swing")
        }
    }

    /// Blocking engagement: both arms punch out locked at chest height and
    /// the figure works a short fore-aft shove cycle for the step — OL/DL
    /// pairs read as locked up chest to chest instead of jogging to spots.
    private func blockEngage(nodeIndex: Int, duration: TimeInterval, style: BlockStyle = .drive) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }

        // Hands punch out and lock onto the chest — shared by the engaged
        // styles; the cut block keeps the hands low instead.
        func punchArms(x: CGFloat, forearm: CGFloat) {
            for (name, inward) in [("arm", CGFloat(0.18)), ("armR", CGFloat(-0.18))] {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                arm.removeAction(forKey: "swing")
                let punch = SCNAction.rotateTo(x: x, y: 0, z: inward, duration: 0.16)
                punch.timingMode = .easeOut
                arm.runAction(punch, forKey: "swing")
                if let fa = arm.childNode(withName: "forearm", recursively: false) {
                    fa.removeAction(forKey: "bend")
                    fa.runAction(SCNAction.rotateTo(x: forearm, y: 0, z: 0, duration: 0.16),
                                 forKey: "bend")
                }
            }
        }

        figure.removeAction(forKey: "shove")
        clearBystanderIdle(figure)

        switch style {
        case .drive:
            // Winner's rep: anticipation (a short load back), then repeated
            // forward drive surges, resolved back to neutral at the whistle.
            // moveBy composes with the gait bob's y moves, so the gait stays.
            punchArms(x: -1.15, forearm: -0.4)
            let load = SCNAction.moveBy(x: 0, y: 0, z: -0.06, duration: 0.12)
            load.timingMode = .easeOut
            let push = SCNAction.moveBy(x: 0, y: 0, z: 0.19, duration: 0.26)
            push.timingMode = .easeInEaseOut
            let recover = SCNAction.moveBy(x: 0, y: 0, z: -0.13, duration: 0.24)
            recover.timingMode = .easeInEaseOut
            let cycles = max(Int(duration / 0.5), 1)
            figure.runAction(SCNAction.sequence([
                load,
                SCNAction.repeat(SCNAction.sequence([push, recover]), count: cycles),
                SCNAction.move(to: SCNVector3Zero, duration: 0.14),
            ]), forKey: "shove")

        case .anchor:
            // Pass-pro set: sit into the block, absorb the bull rush backward
            // then re-anchor forward — net-neutral, everything eased.
            punchArms(x: -1.05, forearm: -0.55)
            let sink = SCNAction.moveBy(x: 0, y: -0.07, z: 0, duration: 0.16)
            sink.timingMode = .easeOut
            let give = SCNAction.moveBy(x: 0, y: 0, z: -0.12, duration: 0.28)
            give.timingMode = .easeInEaseOut
            let anchorBack = SCNAction.moveBy(x: 0, y: 0, z: 0.09, duration: 0.3)
            anchorBack.timingMode = .easeInEaseOut
            let cycles = max(Int(duration / 0.6), 1)
            figure.runAction(SCNAction.sequence([
                sink,
                SCNAction.repeat(SCNAction.sequence([give, anchorBack]), count: cycles),
                SCNAction.move(to: SCNVector3Zero, duration: 0.16),
            ]), forKey: "shove")

        case .pancake:
            // Decisive win: hands punch high, the blocker coils then lunges
            // forward and drives his man to the turf, then straightens up.
            // Owns the figure (gait removed) so the pitch doesn't fight the lean.
            figure.removeAction(forKey: "gait")
            figure.removeAction(forKey: "hop")
            punchArms(x: -1.5, forearm: -0.2)
            let coil = SCNAction.group([
                SCNAction.rotateTo(x: -0.2, y: 0, z: 0, duration: 0.12),
                SCNAction.moveBy(x: 0, y: 0.05, z: -0.06, duration: 0.12),
            ])
            coil.timingMode = .easeOut
            let drive = SCNAction.group([
                SCNAction.rotateTo(x: 0.6, y: 0, z: 0, duration: 0.22),
                SCNAction.moveBy(x: 0, y: -0.14, z: 0.6, duration: 0.22),
            ])
            drive.timingMode = .easeIn
            let rise = SCNAction.group([
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.42),
                SCNAction.move(to: SCNVector3Zero, duration: 0.42),
            ])
            rise.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([
                coil, drive, SCNAction.wait(duration: 0.35), rise,
            ]), forKey: "shove")

        case .whiff:
            // Beaten: a swim/rip reaches over the top, the body turns as his
            // man slips past and he catches himself half a step behind.
            figure.removeAction(forKey: "gait")
            for (name, over) in [("arm", CGFloat(2.6)), ("armR", CGFloat(-1.0))] {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                arm.removeAction(forKey: "swing")
                let reach = SCNAction.rotateTo(x: -1.6, y: 0, z: name == "arm" ? 0.4 : -0.3, duration: 0.14)
                reach.timingMode = .easeOut
                let swipe = SCNAction.rotateTo(x: 0.2, y: 0, z: over, duration: 0.22)
                swipe.timingMode = .easeInEaseOut
                let settle = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.32)
                arm.runAction(SCNAction.sequence([reach, swipe, settle]), forKey: "swing")
            }
            let turn = SCNAction.rotateTo(x: 0, y: 0.7, z: 0, duration: 0.28)
            turn.timingMode = .easeOut
            let stumble = SCNAction.moveBy(x: 0.12, y: 0, z: -0.14, duration: 0.28)
            stumble.timingMode = .easeOut
            let recover = SCNAction.group([
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.4),
                SCNAction.move(to: SCNVector3Zero, duration: 0.4),
            ])
            recover.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([
                SCNAction.group([turn, stumble]), SCNAction.wait(duration: 0.2), recover,
            ]), forKey: "shove")

        case .cut:
            // Cut block: hands down, the blocker pitches low at the legs then
            // pops back up onto his feet.
            figure.removeAction(forKey: "gait")
            figure.removeAction(forKey: "hop")
            for (name, inward) in [("arm", CGFloat(0.1)), ("armR", CGFloat(-0.1))] {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                arm.removeAction(forKey: "swing")
                arm.runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: 0.6, y: 0, z: inward, duration: 0.16),
                    SCNAction.wait(duration: 0.5),
                    SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.3),
                ]), forKey: "swing")
            }
            let anticipate = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.1)
            anticipate.timingMode = .easeOut
            let dive = SCNAction.group([
                SCNAction.rotateTo(x: 0.95, y: 0, z: 0, duration: 0.18),
                SCNAction.moveBy(x: 0, y: -0.39, z: 0.35, duration: 0.18),
            ])
            dive.timingMode = .easeIn
            let up = SCNAction.group([
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.44),
                SCNAction.move(to: SCNVector3Zero, duration: 0.44),
            ])
            up.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([
                anticipate, dive, SCNAction.wait(duration: 0.32), up,
            ]), forKey: "shove")
        }
    }

    /// Pump fake: the throwing arm cocks and half-fires without the ball,
    /// then recovers to the two-hand chest hold. `delay` places it late in
    /// the drop, just before the real throw.
    /// Two pump-fake flavours: the full wind-up double-clutch (a real throwing
    /// motion pulled back at the last instant) or, with `quick`, a short sharp
    /// shoulder shrug that jerks the torso without cocking the arm all the way.
    private func pumpFake(nodeIndex: Int, delay: TimeInterval, quick: Bool = false) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false),
              let arm = figure.childNode(withName: "armR", recursively: false) else { return }
        let windupX: CGFloat = quick ? 1.0 : 1.7
        let windupDur: TimeInterval = quick ? 0.1 : 0.13
        let flickX: CGFloat = quick ? -0.5 : -1.2
        let flickDur: TimeInterval = quick ? 0.09 : 0.12
        let windup = SCNAction.rotateTo(x: windupX, y: 0, z: -0.25, duration: windupDur)
        windup.timingMode = .easeOut
        let halfThrow = SCNAction.rotateTo(x: flickX, y: 0, z: -0.25, duration: flickDur)
        halfThrow.timingMode = .easeIn
        let rechamber = SCNAction.rotateTo(x: -1.0, y: 0, z: -0.28, duration: 0.2)
        arm.runAction(SCNAction.sequence([
            SCNAction.wait(duration: delay), windup, halfThrow, rechamber,
        ]), forKey: "swing")
        // Shoulder shrug into the pump — bigger on the quick fake, which sells
        // the whole thing with the torso rather than the arm.
        if let body = figure.childNode(withName: "body", recursively: false) {
            let twist: CGFloat = quick ? 0.22 : 0.14
            body.removeAction(forKey: "twist")
            body.runAction(SCNAction.sequence([
                SCNAction.wait(duration: delay),
                SCNAction.rotateTo(x: 0, y: twist, z: 0, duration: windupDur),
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: flickDur + 0.12),
            ]), forKey: "twist")
        }
    }

    /// One-shot open-field move on a ball carrier. Every variant is pure
    /// presentation — the carrier's underlying track/timing is untouched, so
    /// the sim's yardage is unchanged. All banks, hops and dips ride easing
    /// (no per-frame work) and run under the "gait"/"spinMove"/"swing" keys so
    /// the next move or `resetGait` clears them seamlessly.
    private func performOpenFieldMove(nodeIndex: Int, kind: OpenFieldMove.Kind) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        // Skeletal path: a mocap evasive move over the locomotion, then return.
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "juke")
            return
        }
        switch kind {
        case .spin:
            // Full 360° turn that dips and rises out of the spin.
            figure.removeAction(forKey: "gait")
            let spin = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 0.45)
            spin.timingMode = .easeInEaseOut
            figure.runAction(spin, forKey: "spinMove")
            let dip = SCNAction.moveBy(x: 0, y: -0.12, z: 0, duration: 0.22)
            dip.timingMode = .easeInEaseOut
            let rise = SCNAction.moveBy(x: 0, y: 0.12, z: 0, duration: 0.23)
            rise.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([dip, rise]), forKey: "hop")
        case .juke:
            // Jab-step cut: a hard plant one way (bank + a quick lateral hop of
            // the whole figure) sold before the path's jig carries him across.
            figure.removeAction(forKey: "gait")
            figure.removeAction(forKey: "hop")
            let plant = SCNAction.rotateTo(x: 0.15, y: 0, z: 0.4, duration: 0.11)
            plant.timingMode = .easeOut
            let cutBack = SCNAction.rotateTo(x: 0.18, y: 0, z: -0.34, duration: 0.14)
            cutBack.timingMode = .easeInEaseOut
            let recover = SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.15)
            recover.timingMode = .easeOut
            figure.runAction(SCNAction.sequence([plant, cutBack, recover]), forKey: "spinMove")
            let jab = SCNAction.moveBy(x: 0.28, y: 0, z: 0, duration: 0.11)
            jab.timingMode = .easeOut
            let ret = SCNAction.moveBy(x: -0.28, y: 0, z: 0, duration: 0.18)
            ret.timingMode = .easeInEaseOut
            figure.runAction(SCNAction.sequence([jab, ret]), forKey: "hop")
        case .stiffArm:
            // Off (right) arm punches straight out into the chaser with a lean
            // into the push.
            figure.removeAction(forKey: "gait")
            let lean = SCNAction.sequence([
                SCNAction.rotateTo(x: 0.24, y: 0, z: -0.16, duration: 0.15),
                SCNAction.wait(duration: 0.4),
                SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.25),
            ])
            lean.timingMode = .easeInEaseOut
            figure.runAction(lean, forKey: "spinMove")
            guard let arm = figure.childNode(withName: "armR", recursively: false) else { return }
            arm.removeAction(forKey: "swing")
            let extend = SCNAction.rotateTo(x: 0.5, y: 0, z: -1.25, duration: 0.15)
            extend.timingMode = .easeOut
            let release = SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.25)
            arm.runAction(SCNAction.sequence([extend, SCNAction.wait(duration: 0.55), release]),
                          forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.15),
                    SCNAction.wait(duration: 0.55),
                    SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.25),
                ]), forKey: "bend")
        case .hurdle:
            // A short leap with the knees tucked — clearing a fallen defender.
            figure.removeAction(forKey: "gait")
            figure.removeAction(forKey: "hop")
            let up = SCNAction.moveBy(x: 0, y: 0.55, z: 0, duration: 0.2)
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -0.55, z: 0, duration: 0.22)
            down.timingMode = .easeIn
            figure.runAction(SCNAction.sequence([up, down]), forKey: "hop")
            let launch = SCNAction.rotateTo(x: -0.1, y: 0, z: 0, duration: 0.2)
            let land = SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.22)
            figure.runAction(SCNAction.sequence([launch, land]), forKey: "spinMove")
            for name in ["leg", "legR"] {
                guard let leg = figure.childNode(withName: name, recursively: false) else { continue }
                leg.removeAction(forKey: "swing")
                leg.runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.2),
                    SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.22),
                ]), forKey: "swing")
                leg.childNode(withName: "shin", recursively: false)?
                    .runAction(SCNAction.sequence([
                        SCNAction.rotateTo(x: 1.0, y: 0, z: 0, duration: 0.2),
                        SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.22),
                    ]), forKey: "bend")
            }
        case .deadLeg:
            // Hesitation stutter: a quick sink-and-hitch that freezes the
            // pursuit, then a snap back upright as he bursts through.
            figure.removeAction(forKey: "gait")
            figure.removeAction(forKey: "hop")
            let sink = SCNAction.moveBy(x: 0, y: -0.14, z: 0, duration: 0.1)
            sink.timingMode = .easeOut
            let hold = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 0.12)
            let pop = SCNAction.moveBy(x: 0, y: 0.1, z: 0, duration: 0.13)
            pop.timingMode = .easeIn
            figure.runAction(SCNAction.sequence([sink, hold, pop]), forKey: "hop")
            let hitch = SCNAction.sequence([
                SCNAction.rotateTo(x: 0.32, y: 0, z: 0.12, duration: 0.1),
                SCNAction.rotateTo(x: 0.28, y: 0, z: -0.08, duration: 0.12),
                SCNAction.rotateTo(x: 0.15, y: 0, z: 0, duration: 0.14),
            ])
            hitch.timingMode = .easeInEaseOut
            figure.runAction(hitch, forKey: "spinMove")
        }
    }

    /// A quick vertical dip-and-recover on the camera — the impact pump
    /// behind a big hit. moveBy, so it composes with any running pan.
    private func cameraBump() {
        guard !kickCameraActive else { return }
        let dip = SCNAction.moveBy(x: 0, y: -0.4, z: 0, duration: 0.08)
        dip.timingMode = .easeOut
        cameraNode.runAction(SCNAction.sequence([dip, dip.reversed()]), forKey: "bump")
    }

    /// The carrier and tackler hit the turf, lie there a beat, and get up.
    /// `getUpDelay` staggers the rise for gang-tackle piles — the last man
    /// on (top of the pile) climbs off first. With `stayDown` the figure
    /// collapses and stays on the turf (injury presentation) — the next
    /// formation move stands him back up, by which point the node already
    /// wears the replacement's number.
    private func fall(nodeIndex: Int, delay: TimeInterval = 0, stayDown: Bool = false,
                      getUpDelay: TimeInterval = 0, style: FallStyle = .forward) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        // Skeletal: the man plays the mocap fall and holds the ground pose until
        // the next move stands him back up (setMoving clears the "fall" key).
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "tackle", delay: delay, hold: true)
            return
        }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "stance")
        figure.removeAction(forKey: "shove")
        clearBystanderIdle(figure)
        // Every man hits the turf at his own angle — a gang pile reads as a
        // heap of bodies, not a row of synchronized dominoes.
        let yaw = Float.random(in: -0.6...0.6)
        let pitch: CGFloat
        let landing: SCNVector3
        let dropTime: TimeInterval
        // Anticipation: a beat of load/recoil before the body commits to the
        // turf so nobody snaps flat from a dead-linear standstill.
        let brace: SCNAction?
        switch style {
        case .forward:
            pitch = CGFloat(-1.45 + yaw * 0.1)
            landing = SCNVector3(0, -0.32, 0.15)
            dropTime = 0.3
            let b = SCNAction.group([
                SCNAction.rotateBy(x: 0.12, y: 0, z: 0, duration: 0.07),
                SCNAction.moveBy(x: 0, y: 0.04, z: -0.04, duration: 0.07),
            ])
            b.timingMode = .easeOut
            brace = b
        case .backward:
            // Feet fly out, shoulders hit last — flat on his back.
            pitch = CGFloat(1.35 + yaw * 0.1)
            landing = SCNVector3(0, -0.3, -0.35)
            dropTime = 0.26
            let b = SCNAction.rotateBy(x: -0.22, y: 0, z: 0, duration: 0.06)
            b.timingMode = .easeOut
            brace = b
        case .dive:
            // Horizontal launch at the legs: fast, flat and long.
            pitch = -1.52
            landing = SCNVector3(0, -0.36, 0.55)
            dropTime = 0.17
            brace = nil   // a diving tackle is already a committed launch
        case .trip:
            // Shoestring: legs cut out, the body pitches hard forward and
            // long, hands flung ahead to break the fall.
            pitch = CGFloat(-1.72 + yaw * 0.08)
            landing = SCNVector3(0, -0.34, 0.5)
            dropTime = 0.22
            let b = SCNAction.group([
                SCNAction.rotateBy(x: 0.16, y: 0, z: 0, duration: 0.06),
                SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.06),
            ])
            b.timingMode = .easeOut
            brace = b
            for name in ["arm", "armR"] {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                arm.removeAction(forKey: "swing")
                arm.runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: -2.4, y: 0, z: name == "arm" ? 0.2 : -0.2, duration: 0.16),
                    SCNAction.wait(duration: 0.9),
                    SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.3),
                ]), forKey: "swing")
            }
        }
        let down = SCNAction.group([
            SCNAction.rotateTo(x: pitch, y: CGFloat(yaw), z: 0, duration: dropTime),
            SCNAction.move(to: landing, duration: dropTime),
        ])
        down.timingMode = .easeIn
        // Follow-through: a small settle bounce as the mass loads onto the turf
        // — the impact doesn't die on a hard linear stop.
        let settle = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.09),
            SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 0.11),
        ])
        settle.timingMode = .easeInEaseOut
        var downSeq: [SCNAction] = [SCNAction.wait(duration: delay)]
        if let brace { downSeq.append(brace) }
        downSeq.append(down)
        downSeq.append(settle)
        if stayDown {
            figure.runAction(SCNAction.sequence(downSeq), forKey: "fall")
            return
        }
        let up = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.45),
            SCNAction.move(to: SCNVector3Zero, duration: 0.45),
        ])
        up.timingMode = .easeInEaseOut
        downSeq.append(SCNAction.wait(duration: 0.8 + getUpDelay))
        downSeq.append(up)
        figure.runAction(SCNAction.sequence(downSeq), forKey: "fall")
    }

    /// Wrap tackle: both of the tackler's arms whip forward and curl around
    /// the carrier as the hit begins, then release once the pile settles.
    /// Runs under the same "swing"/"bend" keys as the run cycle, so the next
    /// snap's `swingLimbs` replaces it seamlessly.
    private func wrapArms(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        // Skeletal path: a mocap tackle over the locomotion, then return.
        if let skel = skeletalDriver(for: figure) {
            skel.play(action: "tackle")
            return
        }
        for (name, inward) in [("arm", CGFloat(0.7)), ("armR", CGFloat(-0.7))] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            let wrap = SCNAction.rotateTo(x: -1.25, y: 0, z: inward, duration: 0.18)
            wrap.timingMode = .easeOut
            let release = SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.3)
            arm.runAction(SCNAction.sequence([wrap, SCNAction.wait(duration: 1.1), release]),
                          forKey: "swing")
            if let forearm = arm.childNode(withName: "forearm", recursively: false) {
                forearm.removeAction(forKey: "bend")
                forearm.runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: -1.2, y: 0, z: 0, duration: 0.18),
                    SCNAction.wait(duration: 1.1),
                    SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.3),
                ]), forKey: "bend")
            }
        }
    }

    /// Touchdown celebration: the scorer leaps with both arms thrown up.
    /// The choreography spikes the ball right after via a short ball arc.
    private func celebrationJump(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "hop")
        // Skeletal path: play the retargeted Victory celebration clip.
        if let skel = skeletalDriver(for: figure) {
            skel.setMoving(false, speed: 0)
            skel.play(action: "celebrate")
            return
        }
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

    /// Goal-line dive: the carrier gathers, lays out flat with the ball
    /// reaching over the pylon, hits the turf stretched out, then pops up for
    /// the celebration. Pure presentation on a scoring carry.
    private func pylonDive(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "hop")
        figure.removeAction(forKey: "stance")
        figure.removeAction(forKey: "spinMove")
        // Ball-side (left) arm thrusts the ball forward over the goal line; the
        // off arm trails back for the layout line.
        if let arm = figure.childNode(withName: "arm", recursively: false) {
            arm.removeAction(forKey: "swing")
            arm.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: -2.5, y: 0, z: 0.15, duration: 0.2),
                SCNAction.wait(duration: 0.9),
                SCNAction.rotateTo(x: 0, y: 0, z: 0.25, duration: 0.3),
            ]), forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2), forKey: "bend")
        }
        if let armR = figure.childNode(withName: "armR", recursively: false) {
            armR.removeAction(forKey: "swing")
            armR.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: 1.0, y: 0, z: -0.3, duration: 0.2),
                SCNAction.wait(duration: 0.9),
                SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.3),
            ]), forKey: "swing")
        }
        let gather = SCNAction.group([
            SCNAction.rotateTo(x: 0.2, y: 0, z: 0, duration: 0.1),
            SCNAction.moveBy(x: 0, y: -0.1, z: 0, duration: 0.1),
        ])
        gather.timingMode = .easeOut
        let launch = SCNAction.group([
            SCNAction.rotateTo(x: -1.5, y: 0, z: 0, duration: 0.22),
            SCNAction.move(to: SCNVector3(0, 0.15, 0.7), duration: 0.22),
        ])
        launch.timingMode = .easeOut
        let land = SCNAction.group([
            SCNAction.rotateTo(x: -1.62, y: 0, z: 0, duration: 0.16),
            SCNAction.move(to: SCNVector3(0, -0.34, 1.0), duration: 0.16),
        ])
        land.timingMode = .easeIn
        let settle = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.09),
            SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 0.11),
        ])
        settle.timingMode = .easeInEaseOut
        let rise = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5),
            SCNAction.move(to: SCNVector3Zero, duration: 0.5),
        ])
        rise.timingMode = .easeInEaseOut
        figure.runAction(SCNAction.sequence([
            gather, launch, land, settle, SCNAction.wait(duration: 0.5), rise,
        ]), forKey: "fall")
    }

    /// QB slide: he gives himself up feet-first — leans back, drops into a
    /// low protective slide with the hands up, then climbs back to his feet.
    private func qbSlide(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        figure.removeAction(forKey: "gait")
        figure.removeAction(forKey: "hop")
        figure.removeAction(forKey: "stance")
        // Anticipation: a quick gather-up before he sits it down.
        let gather = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 0.1)
        gather.timingMode = .easeOut
        // Sit back into the slide — torso tips back, hips drop.
        let sit = SCNAction.group([
            SCNAction.rotateTo(x: 0.75, y: 0, z: 0, duration: 0.22),
            SCNAction.move(to: SCNVector3(0, -0.34, -0.12), duration: 0.22),
        ])
        sit.timingMode = .easeOut
        let hold = SCNAction.wait(duration: 0.5)
        let up = SCNAction.group([
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.45),
            SCNAction.move(to: SCNVector3Zero, duration: 0.45),
        ])
        up.timingMode = .easeInEaseOut
        figure.runAction(SCNAction.sequence([gather, sit, hold, up]), forKey: "fall")
        // Feet kick forward ahead of the hips, then recover under him.
        for name in ["leg", "legR"] {
            guard let leg = figure.childNode(withName: name, recursively: false) else { continue }
            leg.removeAction(forKey: "swing")
            leg.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: -0.6, y: 0, z: 0, duration: 0.22),
                SCNAction.wait(duration: 0.5),
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.4),
            ]), forKey: "swing")
        }
        // Hands up out of harm's way.
        for name in ["arm", "armR"] {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            arm.removeAction(forKey: "swing")
            arm.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: -0.4, y: 0, z: name == "arm" ? 1.4 : -1.4, duration: 0.2),
                SCNAction.wait(duration: 0.5),
                SCNAction.rotateTo(x: 0, y: 0, z: name == "arm" ? 0.25 : -0.25, duration: 0.4),
            ]), forKey: "swing")
        }
    }

    /// Forward lunge: the carrier stretches the ball out ahead to reach the
    /// marker (or goal line) as he goes down. Arms only — the body's forward
    /// fall runs concurrently on its own key.
    private func lunge(nodeIndex: Int) {
        guard let node = playerNode(at: nodeIndex),
              let figure = node.childNode(withName: "figure", recursively: false) else { return }
        guard let arm = figure.childNode(withName: "arm", recursively: false) else { return }
        arm.removeAction(forKey: "swing")
        arm.runAction(SCNAction.sequence([
            SCNAction.rotateTo(x: -2.5, y: 0, z: 0.15, duration: 0.18),
            SCNAction.wait(duration: 0.9),
            SCNAction.rotateTo(x: 0, y: 0, z: 0.25, duration: 0.3),
        ]), forKey: "swing")
        arm.childNode(withName: "forearm", recursively: false)?
            .runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.18), forKey: "bend")
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
        figure.removeAction(forKey: "shove")
        figure.removeAction(forKey: "spinMove")
        clearBystanderIdle(figure)
        figure.position = SCNVector3Zero
        figure.eulerAngles = SCNVector3Zero
        if let body = figure.childNode(withName: "body", recursively: false) {
            body.removeAction(forKey: "twist")
            body.eulerAngles = SCNVector3Zero
        }
        // Re-anchor the idle breath loop from the fresh rest pose (a loop cut
        // mid-cycle would otherwise leave a tiny cumulative offset).
        let allPlayers = homePlayerNodes + awayPlayerNodes
        startIdle(on: node, seed: allPlayers.firstIndex(where: { $0 === node }) ?? 0)
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
        for path in step.paths {
            duration = max(duration, path.duration)
        }
        switch step.ballMove {
        case .arc(_, _, let ballDuration, _), .slide(_, let ballDuration):
            duration = max(duration, ballDuration)
        case .snap(_, let shotgun):
            // The snap flight is re-timed on the same clock as the steps
            // (see `runSnapExchange`), so its budget scales too.
            duration = max(duration, Self.snapDuration(shotgun: shotgun) / currentPlaybackRate)
        default:
            break
        }
        return duration
    }

    /// Receivers whose hands went up under a live arc: when the very next
    /// ball attachment lands on one of them, that beat IS the catch and the
    /// catch-pop cue fires (completions, picks, kickoff fields — never an
    /// incompletion, whose arc dies into a slide instead).
    private var pendingCatchNodes: Set<Int> = []

    /// Fires the SFX a step implies — the explicit cue slot plus contact
    /// sounds derived from the ball move and the tackle/catch lists. Kept
    /// out of `execute` proper so the animation path stays readable.
    private func playStepAudio(_ step: PlayStep) {
        if let cue = step.sound { AudioDirector.shared.play(cue) }
        // Contact: one thud per contact beat (gang tackles share it); a big
        // hit hits harder and pulls the crowd up with the camera bump.
        if !step.bigHits.isEmpty {
            AudioDirector.shared.play(.hitBig)
            AudioDirector.shared.play(.crowdSwell)
        } else if !step.falls.isEmpty || !step.wraps.isEmpty || !step.diveFalls.isEmpty {
            AudioDirector.shared.play(.hitLight)
        }
        switch step.ballMove {
        case .snap:
            AudioDirector.shared.play(.snap)
            pendingCatchNodes = []
        case .arc:
            pendingCatchNodes = Set(step.reaches)
        case .carry(let nodeIndex), .carryChest(let nodeIndex):
            if pendingCatchNodes.contains(nodeIndex) {
                AudioDirector.shared.play(.catchPop)
            }
            pendingCatchNodes = []
        case .slide:
            pendingCatchNodes = []
        case nil:
            break
        }
    }

    /// Kicks off everything inside a single step: player moves, pulses, falls,
    /// reaches, celebrations, ball behavior — plus the follow-cam on long carries.
    private func execute(step: PlayStep) {
        playStepAudio(step)
        // Staggered get-offs: a node with a reaction delay launches its move
        // a beat late (dies with the play generation like every queued beat).
        let generation = playGeneration
        for move in step.moves {
            guard let node = playerNode(at: move.nodeIndex) else { continue }
            let backpedal = step.backpedals.contains(move.nodeIndex)
            if let delay = step.startDelays[move.nodeIndex], delay > 0.02 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.playGeneration == generation else { return }
                    self.run(node: node, to: move.to, duration: move.duration, key: "playMove",
                             backpedal: backpedal)
                }
            } else {
                run(node: node, to: move.to, duration: move.duration, key: "playMove",
                    backpedal: backpedal)
            }
        }
        for path in step.paths where !path.points.isEmpty {
            let backpedal = step.backpedals.contains(path.nodeIndex)
            if let delay = step.startDelays[path.nodeIndex], delay > 0.02 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.playGeneration == generation else { return }
                    self.runPath(nodeIndex: path.nodeIndex, points: path.points,
                                 duration: path.duration, backpedal: backpedal)
                }
            } else {
                runPath(nodeIndex: path.nodeIndex, points: path.points, duration: path.duration,
                        backpedal: backpedal)
            }
        }

        let stepDuration = effectiveDuration(of: step)
        for index in step.pulses { pulse(nodeIndex: index) }
        for index in step.wraps { wrapArms(nodeIndex: index) }
        for index in step.blocks {
            blockEngage(nodeIndex: index, duration: stepDuration,
                        style: step.blockStyles[index] ?? .drive)
        }
        for index in step.pumpFakes {
            pumpFake(nodeIndex: index, delay: max(stepDuration - 0.65, 0.15),
                     quick: step.pumpFakeQuick)
        }
        // The ball's origin this step (the passer) — receivers turn back to it.
        let passer: SCNNode? = {
            if case let .arc(_, _, _, from) = step.ballMove, let from {
                return playerNode(at: from)
            }
            return nil
        }()
        // When the ball is in the air this step, sync the catch to its arrival
        // (skeletal catch clips fire on a delay so the hands go up as it lands).
        let arriveIn: TimeInterval = {
            if case let .arc(_, _, d, _) = step.ballMove { return d }
            return 0
        }()
        for index in step.reaches {
            let style = step.catchStyles[index] ?? .reach
            let yaw = catchTurnYaw(nodeIndex: index, style: style, passer: passer)
            switch style {
            case .reach: reach(nodeIndex: index, turnYaw: yaw, arriveIn: arriveIn)
            case .overShoulder: overShoulderReach(nodeIndex: index, turnYaw: yaw, arriveIn: arriveIn)
            case .dive: divingCatch(nodeIndex: index, turnYaw: yaw, arriveIn: arriveIn)
            case .toeTap: toeTapReach(nodeIndex: index, turnYaw: yaw, arriveIn: arriveIn)
            }
        }
        for index in step.celebrates { celebrationJump(nodeIndex: index) }
        // Falls stagger DOWN in list order; the pile unstacks in reverse at
        // ragged 0.3-0.7s beats — the last man on (top of the pile) is the
        // first back on his feet, and nobody pops up in lockstep.
        var riseDelay: TimeInterval = 0
        var riseDelays = [TimeInterval](repeating: 0, count: step.falls.count)
        for offset in stride(from: step.falls.count - 2, through: 0, by: -1) {
            riseDelay += TimeInterval.random(in: 0.3...0.7)
            riseDelays[offset] = riseDelay
        }
        for (offset, index) in step.falls.enumerated() {
            fall(nodeIndex: index, delay: Double(offset) * 0.12,
                 getUpDelay: riseDelays[offset])
        }
        // Big hits: the carrier flies onto his back and the camera pumps.
        for index in step.bigHits { fall(nodeIndex: index, style: .backward) }
        if !step.bigHits.isEmpty { cameraBump() }
        for index in step.diveFalls { fall(nodeIndex: index, style: .dive) }
        // Shoestring trips, goal-line pylon dives, QB slides, marker lunges.
        for index in step.trips { fall(nodeIndex: index, style: .trip) }
        for index in step.pylonDives { pylonDive(nodeIndex: index) }
        for index in step.qbSlides { qbSlide(nodeIndex: index) }
        for index in step.lunges { lunge(nodeIndex: index) }
        // Open-field moves fire mid-step at their scheduled beats; they die
        // with the play generation like every queued step.
        if !step.openField.isEmpty {
            let generation = playGeneration
            for move in step.openField {
                DispatchQueue.main.asyncAfter(deadline: .now() + move.delay) { [weak self] in
                    guard let self, self.playGeneration == generation else { return }
                    self.performOpenFieldMove(nodeIndex: move.nodeIndex, kind: move.kind)
                }
            }
        }

        switch step.ballMove {
        case .carry(let nodeIndex), .carryChest(let nodeIndex):
            if case .carryChest = step.ballMove {
                attachBall(toPlayerIndex: nodeIndex, chest: true)
            } else {
                attachBall(toPlayerIndex: nodeIndex)
            }
        case .snap(let toNodeIndex, let shotgun):
            runSnapExchange(to: toNodeIndex, shotgun: shotgun)
        case .arc(let to, let apex, let duration, let from):
            runBallArc(to: to, apex: apex, duration: duration, from: from, style: step.throwStyle)
        case .slide(let to, let duration):
            runBallSlide(to: to, duration: duration)
        case nil:
            break
        }
        // The live follow rig tracks the ball per frame (no stepwise pans
        // here anymore — carriers riding in `paths` were invisible to the
        // old move-based trigger and parked the camera at the LOS); the
        // precipitation slab still moves per step.
        driftWeatherEmitter(for: step)
    }

    /// Parents the ball to a player so it rides along with every move.
    /// `chest` holds it in both hands at the chest (QB dropback) instead of
    /// the under-arm tuck.
    private func attachBall(toPlayerIndex index: Int, chest: Bool = false) {
        guard let node = playerNode(at: index) else { return }
        // Any attach claims the ball for the token guard (see runSnapExchange).
        ballHandoffToken += 1
        guard ballNode.parent !== node || carryingChest != chest else { return }
        // A hand-to-hand exchange (handoff, pitch reception, lateral): the
        // giver punches the ball out toward the taker and sheds his carry
        // pose — the ball never teleports off a frozen giver.
        let giverIndex = carryingIndex
        let giverChest = carryingChest
        carryingIndex = index
        carryingChest = chest
        if let giverIndex, giverIndex != index {
            handoffGesture(giverIndex: giverIndex, chest: giverChest, toward: node)
        }
        ballNode.removeAllActions()
        ballNode.eulerAngles = SCNVector3Zero
        ballNode.removeFromParentNode()
        node.addChildNode(ballNode)
        // Chest: squarely in front in both hands; tuck: under the left arm.
        ballNode.position = chest
            ? SCNVector3(0, 0.34, 0.33)
            : SCNVector3(-0.32, 0.28, 0.18)

        // Carry pose right away (swingLimbs keeps it during moves).
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        if chest {
            for (name, inward) in [("arm", CGFloat(0.28)), ("armR", CGFloat(-0.28))] {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                arm.removeAction(forKey: "swing")
                arm.runAction(SCNAction.rotateTo(x: -1.0, y: 0, z: inward, duration: 0.18), forKey: "swing")
                arm.childNode(withName: "forearm", recursively: false)?
                    .runAction(SCNAction.rotateTo(x: -1.1, y: 0, z: 0, duration: 0.18), forKey: "bend")
            }
        } else if let arm = figure.childNode(withName: "arm", recursively: false) {
            arm.removeAction(forKey: "swing")
            arm.runAction(SCNAction.rotateTo(x: -0.55, y: 0, z: 0.35, duration: 0.2), forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: -1.35, y: 0, z: 0, duration: 0.2), forKey: "bend")
            // The right arm may still hold a stale chest pose from a drop.
            if let armR = figure.childNode(withName: "armR", recursively: false),
               armR.action(forKey: "swing") == nil {
                armR.runAction(SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.2), forKey: "swing")
            }
        }
    }

    /// Re-parents the ball to the root node, preserving its world position.
    private func detachBallToRoot() {
        if let previous = playerNode(at: carryingIndex ?? -1),
           let figure = previous.childNode(withName: "figure", recursively: false) {
            let arms = carryingChest ? ["arm", "armR"] : ["arm"]
            for name in arms {
                guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
                let rest: CGFloat = name == "arm" ? 0.25 : -0.25
                arm.runAction(SCNAction.rotateTo(x: 0, y: 0, z: rest, duration: 0.2), forKey: "swing")
                arm.childNode(withName: "forearm", recursively: false)?
                    .runAction(SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.2), forKey: "bend")
            }
        }
        carryingIndex = nil
        carryingChest = false
        guard ballNode.parent !== rootNode else { return }
        let worldPosition = ballNode.worldPosition
        ballNode.removeFromParentNode()
        rootNode.addChildNode(ballNode)
        ballNode.position = worldPosition
    }

    /// The C→QB exchange: the ball homes on the QB node (he may already be
    /// stepping into his drop) and attaches into the chest carry on arrival.
    /// Under center it is a fast hand-to-hand transfer; shotgun a low toss
    /// with a lazy end-over-end wobble. A ball left absurdly far from the
    /// QB (stale spot) just attaches without the visual.
    private func runSnapExchange(to index: Int, shotgun: Bool) {
        guard let node = playerNode(at: index) else { return }
        ballHandoffToken += 1
        detachBallToRoot()
        ballNode.removeAllActions()
        let start = ballNode.position
        let dx = node.position.x - start.x
        let dz = node.position.z - start.z
        guard dx * dx + dz * dz < 144 else {
            attachBall(toPlayerIndex: index, chest: true)
            return
        }
        // The flight rides the playback clock so it finishes in step with the
        // scaled timeline instead of overrunning it at fast speeds.
        let duration = Self.snapDuration(shotgun: shotgun) / currentPlaybackRate
        let apex: Float = shotgun ? 0.8 : 0
        let arc = SCNAction.customAction(duration: duration) { [weak node] ball, elapsed in
            guard let node else { return }
            let t = max(0, min(Float(elapsed) / Float(duration), 1))
            let target = node.position  // homes on the moving QB
            ball.position = SCNVector3(
                start.x + (target.x - start.x) * t,
                start.y + (0.85 - start.y) * t + apex * 4 * t * (1 - t),
                start.z + (target.z - start.z) * t
            )
        }
        ballNode.runAction(arc, forKey: "ballMove")
        if shotgun {
            ballNode.runAction(SCNAction.rotateBy(x: -.pi, y: 0, z: 0, duration: duration),
                               forKey: "ballSpin")
        }
        let generation = playGeneration
        let token = ballHandoffToken
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            // Skip if a later ball move (e.g. the throw on a toss) already
            // claimed the ball — never snatch it back mid-flight.
            guard let self, self.playGeneration == generation,
                  self.ballHandoffToken == token else { return }
            self.ballNode.eulerAngles = SCNVector3Zero
            self.attachBall(toPlayerIndex: index, chest: true)
        }
    }

    /// Flies the ball along a parabola. The launch point is always the
    /// passer's hands: `from` (or the live carry) resolves the thrower and
    /// the flight starts at his ANIMATED chest position — never a stale spot.
    private func runBallArc(to target: SCNVector3, apex: Float, duration: TimeInterval,
                            from passerIndex: Int? = nil, style: ThrowStyle? = nil) {
        // Claim the ball so any pending snap-attach for this play no-ops.
        ballHandoffToken += 1
        // Whoever carries the ball is the passer; a snap→throw race can leave
        // the carry unassigned, so fall back to the passer the call named.
        let thrower = playerNode(at: carryingIndex ?? passerIndex ?? -1)
        // Invariant: capture the hand release point BEFORE the detach clears
        // the carry, from the thrower's presentation (his on-screen spot).
        let release = thrower.map { ballReleasePoint(for: $0) }
        detachBallToRoot()
        ballNode.removeAllActions()
        guard duration > 0 else {
            ballNode.position = release ?? target
            return
        }
        // A short low flip is a pitch (toss / screen shovel) with a light
        // lateral scoop; a real arc is an overhead throw. Kicks (no passer)
        // get no arm at all.
        if let thrower {
            if apex <= 2.0 { pitchMotion(of: thrower, toward: target) }
            else { throwMotion(of: thrower, style: style ?? .overhand) }
        }

        let start = release ?? ballNode.position
        ballNode.position = start
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

    /// Per-style shaping of the throwing motion. Amplitudes and durations
    /// only — the actual node wiring lives in `throwMotion`.
    private struct ThrowShape {
        var windupX: CGFloat        // how far the arm cocks back
        var armZ: CGFloat           // elbow carriage (more negative = 3/4 out)
        var releaseX: CGFloat       // how far the arm whips through
        var windupDur: TimeInterval
        var releaseDur: TimeInterval
        var trunkPitch: CGFloat     // forward follow-through onto the front foot
        var trunkTilt: CGFloat      // sideways lean (off-foot bails away)
        var shoulderTwist: CGFloat  // torso rotation driving the arm through
        var frontLegStep: CGFloat   // plant of the lead leg (negative = forward)
        var settle: TimeInterval    // how long the follow-through hangs
    }

    private func throwShape(_ style: ThrowStyle) -> ThrowShape {
        switch style {
        case .overhand:
            return ThrowShape(windupX: 2.2, armZ: -0.25, releaseX: -2.6,
                              windupDur: 0.16, releaseDur: 0.18, trunkPitch: 0.24,
                              trunkTilt: 0, shoulderTwist: 0.22, frontLegStep: -0.5,
                              settle: 0.2)
        case .sidearm:
            // Elbow drops out to the side, short quick flick, minimal weight
            // transfer — the 3/4 out-breaking dart.
            return ThrowShape(windupX: 1.5, armZ: -0.7, releaseX: -1.9,
                              windupDur: 0.12, releaseDur: 0.12, trunkPitch: 0.12,
                              trunkTilt: 0.1, shoulderTwist: 0.3, frontLegStep: -0.3,
                              settle: 0.12)
        case .offFoot:
            // Unbalanced under pressure: arm gets there but the trunk bails
            // away instead of driving forward — no lead-leg plant.
            return ThrowShape(windupX: 1.9, armZ: -0.35, releaseX: -2.2,
                              windupDur: 0.14, releaseDur: 0.15, trunkPitch: -0.14,
                              trunkTilt: -0.28, shoulderTwist: 0.16, frontLegStep: 0.15,
                              settle: 0.18)
        case .lob:
            // Deep touch: a big wind-up, a slow high finish, full weight over.
            return ThrowShape(windupX: 2.55, armZ: -0.25, releaseX: -2.7,
                              windupDur: 0.2, releaseDur: 0.26, trunkPitch: 0.3,
                              trunkTilt: 0, shoulderTwist: 0.26, frontLegStep: -0.6,
                              settle: 0.26)
        case .bullet:
            // Deep drive: full wind-up snapped through on a fast flat release.
            return ThrowShape(windupX: 2.45, armZ: -0.22, releaseX: -2.9,
                              windupDur: 0.16, releaseDur: 0.12, trunkPitch: 0.3,
                              trunkTilt: 0, shoulderTwist: 0.34, frontLegStep: -0.55,
                              settle: 0.2)
        }
    }

    /// The passer's right arm cocks back and snaps forward as the ball
    /// releases into its arc, then settles back to neutral. The trunk follows
    /// through (a pitch + shoulder rotation + a lead-leg plant) timed with the
    /// release; the off hand releases the chest carry to neutral. `style`
    /// shapes the whole motion — a soft deep lob, a driven bullet, a quick
    /// 3/4 sidearm out, or an unbalanced off-the-back-foot heave.
    private func throwMotion(of node: SCNNode, style: ThrowStyle = .overhand) {
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        if let skel = skeletalDriver(for: figure) { skel.play(action: "throw"); return }
        guard let arm = figure.childNode(withName: "armR", recursively: false) else { return }
        let s = throwShape(style)
        arm.removeAction(forKey: "swing")
        let windup = SCNAction.rotateTo(x: s.windupX, y: 0, z: s.armZ, duration: s.windupDur)
        windup.timingMode = .easeOut
        let release = SCNAction.rotateTo(x: s.releaseX, y: 0, z: s.armZ, duration: s.releaseDur)
        release.timingMode = .easeIn
        let neutral = SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.3)
        neutral.timingMode = .easeInEaseOut
        arm.runAction(SCNAction.sequence([windup, release,
                                          SCNAction.wait(duration: s.settle), neutral]),
                      forKey: "swing")
        // Forearm wrist snap: cocked back during the wind-up, whipped straight
        // through the release — the crack that sells the throw.
        if let forearm = arm.childNode(withName: "forearm", recursively: false) {
            forearm.removeAction(forKey: "bend")
            forearm.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: -1.2, y: 0, z: 0, duration: s.windupDur),
                SCNAction.rotateTo(x: 0.1, y: 0, z: 0, duration: s.releaseDur),
                SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.3),
            ]), forKey: "bend")
        }
        // The off (left) hand lets go of the two-hand carry and drops to
        // neutral so the QB doesn't finish frozen in the chest hold.
        if let offArm = figure.childNode(withName: "arm", recursively: false) {
            offArm.removeAction(forKey: "swing")
            let drop = SCNAction.rotateTo(x: 0, y: 0, z: 0.25, duration: s.windupDur + s.releaseDur)
            drop.timingMode = .easeInEaseOut
            offArm.runAction(drop, forKey: "swing")
            offArm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.2), forKey: "bend")
        }

        // Follow-through: the trunk pitches (or bails, off-foot) and the
        // shoulders rotate through the release, then straighten.
        figure.removeAction(forKey: "gait")
        let lean = SCNAction.sequence([
            SCNAction.wait(duration: s.windupDur),
            SCNAction.rotateTo(x: s.trunkPitch, y: 0, z: s.trunkTilt, duration: s.releaseDur),
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3),
        ])
        lean.timingMode = .easeInEaseOut
        figure.runAction(lean, forKey: "gait")
        if let body = figure.childNode(withName: "body", recursively: false) {
            body.removeAction(forKey: "twist")
            body.runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: 0, y: s.shoulderTwist, z: 0, duration: s.windupDur),
                SCNAction.rotateTo(x: 0, y: -s.shoulderTwist * 0.6, z: 0, duration: s.releaseDur),
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3),
            ]), forKey: "twist")
        }
        if let leg = figure.childNode(withName: "leg", recursively: false) {
            leg.removeAction(forKey: "swing")
            leg.runAction(SCNAction.sequence([
                SCNAction.wait(duration: s.windupDur - 0.02),
                SCNAction.rotateTo(x: s.frontLegStep, y: 0, z: 0, duration: 0.16),
                SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3),
            ]), forKey: "swing")
        }
    }

    /// The world point a throw or pitch leaves from: the passer's ANIMATED
    /// (presentation) chest-carry position, so the ball always launches from
    /// his hands — never a stale model transform or the snap's LOS spot.
    private func ballReleasePoint(for node: SCNNode) -> SCNVector3 {
        let carry = SCNVector3(0, 0.34, 0.33)  // the chest-carry local offset
        return node.presentation.convertPosition(carry, to: nil)
    }

    /// A pitch out of the QB's hands (toss sweep, screen shovel): a quick
    /// glance/turn toward the pitch man, then a light underhand flip of the
    /// right arm out to that side — lower and softer than `throwMotion`.
    private func pitchMotion(of node: SCNNode, toward target: SCNVector3) {
        // Turn a fraction toward the pitch man before the flip (a glance, not
        // a spin) so the release faces the ball's direction.
        let here = node.presentation.worldPosition
        let desired = atan2(target.x - here.x, target.z - here.z)
        let current = node.eulerAngles.y
        let delta = atan2(sin(desired - current), cos(desired - current))
        let turn = SCNAction.rotateTo(x: 0, y: CGFloat(current + delta * 0.45), z: 0,
                                      duration: 0.14, usesShortestUnitArc: true)
        node.runAction(turn, forKey: "pitchTurn")

        guard let figure = node.childNode(withName: "figure", recursively: false),
              let arm = figure.childNode(withName: "armR", recursively: false) else { return }
        arm.removeAction(forKey: "swing")
        // Underhand scoop: cock low and out, flip across, settle to neutral.
        let load = SCNAction.rotateTo(x: -0.7, y: 0, z: -0.85, duration: 0.12)
        load.timingMode = .easeOut
        let flip = SCNAction.rotateTo(x: 0.4, y: 0, z: -0.15, duration: 0.16)
        flip.timingMode = .easeIn
        let neutral = SCNAction.rotateTo(x: 0, y: 0, z: -0.25, duration: 0.3)
        neutral.timingMode = .easeInEaseOut
        arm.runAction(SCNAction.sequence([load, flip, SCNAction.wait(duration: 0.12), neutral]),
                      forKey: "swing")
        arm.childNode(withName: "forearm", recursively: false)?
            .runAction(SCNAction.sequence([
                SCNAction.rotateTo(x: -0.6, y: 0, z: 0, duration: 0.12),
                SCNAction.rotateTo(x: -0.1, y: 0, z: 0, duration: 0.32),
            ]), forKey: "bend")
    }

    /// The ball leaving the giver's hands into the next carrier's: his near
    /// arms punch out toward the taker for a beat, then fall back to neutral —
    /// the giver never freezes in a stale carry pose after a handoff.
    private func handoffGesture(giverIndex: Int, chest: Bool, toward taker: SCNNode) {
        guard let giver = playerNode(at: giverIndex),
              let figure = giver.childNode(withName: "figure", recursively: false) else { return }
        // Chest carry extends both hands (a mesh handoff); a tuck extends the
        // ball hand only. Rest angles match the carry-release poses.
        let arms = chest ? ["arm", "armR"] : ["arm"]
        for name in arms {
            guard let arm = figure.childNode(withName: name, recursively: false) else { continue }
            let rest: CGFloat = name == "arm" ? 0.25 : -0.25
            arm.removeAction(forKey: "swing")
            let extend = SCNAction.rotateTo(x: -1.15, y: 0, z: rest * 0.4, duration: 0.14)
            extend.timingMode = .easeOut
            let relax = SCNAction.rotateTo(x: 0, y: 0, z: rest, duration: 0.28)
            relax.timingMode = .easeInEaseOut
            arm.runAction(SCNAction.sequence([extend, SCNAction.wait(duration: 0.08), relax]),
                          forKey: "swing")
            arm.childNode(withName: "forearm", recursively: false)?
                .runAction(SCNAction.sequence([
                    SCNAction.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.14),
                    SCNAction.wait(duration: 0.08),
                    SCNAction.rotateTo(x: -0.15, y: 0, z: 0, duration: 0.28),
                ]), forKey: "bend")
        }
    }

    /// Slides the ball flat along the ground (snaps, rolling punts, dead balls).
    private func runBallSlide(to target: SCNVector3, duration: TimeInterval) {
        ballHandoffToken += 1
        detachBallToRoot()
        ballNode.removeAllActions()
        let action = SCNAction.move(to: target, duration: duration)
        action.timingMode = .easeOut
        ballNode.runAction(action, forKey: "ballMove")
    }

    /// Rewrites the floating jersey number AND the chest/back decals on an
    /// existing player node (substitutions and injuries renumber in place).
    private func updateJerseyNumber(on node: SCNNode, to number: Int) {
        guard let numberNode = node.childNode(withName: "number", recursively: false),
              let text = numberNode.geometry as? SCNText,
              (text.string as? String) != "\(number)" else { return }
        text.string = "\(number)"

        // Re-center the pivot for the new digit width
        let (minB, maxB) = numberNode.boundingBox
        numberNode.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        node.name = "player_\(number)"
        updateNumberDecals(on: node, number: number, jersey: jerseyColor(of: node))
    }

    // MARK: - Jersey Number Decals

    /// Rendered digit textures, cached per number + text shade — 22 players
    /// share a handful of images instead of re-rendering every snap.
    private static var numberTextureCache: [String: UIImage] = [:]

    /// A transparent square with the jersey number drawn in a heavy athletic
    /// weight: white on dark jerseys, near-black on white ones — each with a
    /// thin counter-shade outline so the digits keep reading on mid-tone
    /// jerseys either side of the luminance cut. 256 px so the digits stay
    /// crisp in the tight coach shot.
    private static func numberTexture(_ number: Int, darkText: Bool) -> UIImage {
        let key = "\(number)-\(darkText ? "d" : "l")"
        if let cached = numberTextureCache[key] { return cached }
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let text = "\(number)" as NSString
            let font = UIFont.monospacedDigitSystemFont(ofSize: 156, weight: .heavy)
            let fill = darkText ? UIColor(white: 0.12, alpha: 1) : UIColor.white
            let halo = darkText ? UIColor(white: 1.0, alpha: 0.85)
                                : UIColor(white: 0.1, alpha: 0.85)
            let bounds = text.size(withAttributes: [.font: font])
            let origin = CGPoint(x: (size.width - bounds.width) / 2,
                                 y: (size.height - bounds.height) / 2)
            // Halo drawn by hand (8 offset passes under the fill pass):
            // NSAttributedString's strokeWidth/strokeColor pair renders the
            // fill with the STROKE shade on this path, which inverted the
            // digits (white-on-white chest numbers) — so no stroke attrs.
            for dx in [-3, 0, 3] {
                for dy in [-3, 0, 3] where !(dx == 0 && dy == 0) {
                    text.draw(at: CGPoint(x: origin.x + CGFloat(dx), y: origin.y + CGFloat(dy)),
                              withAttributes: [.font: font, .foregroundColor: halo])
                }
            }
            text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: fill])
        }
        numberTextureCache[key] = image
        return image
    }

    /// Rendered team-abbreviation textures for the helmet side decals,
    /// cached per abbreviation + text shade (same economy as numberTexture).
    private static var abbreviationTextureCache: [String: UIImage] = [:]

    /// A transparent square with the team abbreviation ("GB", "KC") in the
    /// same heavy athletic weight as the jersey numbers: white on dark
    /// helmet shells, near-black on light ones. 256 px for the close shot.
    private static func abbreviationTexture(_ abbreviation: String, darkText: Bool) -> UIImage {
        let key = "\(abbreviation)-\(darkText ? "d" : "l")"
        if let cached = abbreviationTextureCache[key] { return cached }
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let text = abbreviation as NSString
            // Three-letter marks ("JAX") shrink to stay inside the shell.
            let fontSize: CGFloat = abbreviation.count > 2 ? 92 : 120
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: darkText ? UIColor(white: 0.12, alpha: 1) : UIColor.white,
            ]
            let bounds = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size.width - bounds.width) / 2,
                                  y: (size.height - bounds.height) / 2),
                      withAttributes: attributes)
        }
        abbreviationTextureCache[key] = image
        return image
    }

    /// Perceived-luminance check deciding the decal text shade for a jersey.
    private static func isLightColor(_ color: UIColor) -> Bool {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.55
    }

    /// The figure's current JERSEY diffuse (decides decal contrast).
    private func jerseyColor(of node: SCNNode) -> UIColor {
        var found: UIColor?
        node.enumerateHierarchy { child, stop in
            for material in child.geometry?.materials ?? [] where material.name == "JERSEY" {
                found = material.diffuse.contents as? UIColor
                stop.pointee = true
            }
        }
        return found ?? .white
    }

    /// Chest + back number decals: thin planes hovering just off the torso
    /// surface (the Madden-2000 read). Attached to the "body" node so the
    /// running torso twist carries them; positions come from the torso's own
    /// bounding box, so kit and procedural figures both wear them right.
    private func addNumberDecals(to body: SCNNode, number: Int, jersey: UIColor) {
        let (minB, maxB) = body.boundingBox
        let texture = Self.numberTexture(number, darkText: Self.isLightColor(jersey))
        let chestY = minB.y + (maxB.y - minB.y) * 0.6
        let centerX = (minB.x + maxB.x) / 2
        let placements: [(name: String, z: Float, yaw: Float)] = [
            ("numberFront", maxB.z + 0.02, 0),
            ("numberBack", minB.z - 0.02, .pi),
        ]
        for placement in placements {
            let plane = SCNPlane(width: 0.34, height: 0.34)
            let material = SCNMaterial()
            material.name = "NUMBER"
            material.diffuse.contents = texture
            material.lightingModel = .constant
            plane.materials = [material]
            let decal = SCNNode(geometry: plane)
            decal.name = placement.name
            decal.castsShadow = false
            decal.position = SCNVector3(centerX, chestY, placement.z)
            decal.eulerAngles = SCNVector3(0, placement.yaw, 0)
            body.addChildNode(decal)
        }
    }

    /// Re-points both torso decals at the texture for `number` on `jersey`.
    private func updateNumberDecals(on node: SCNNode, number: Int, jersey: UIColor) {
        let texture = Self.numberTexture(number, darkText: Self.isLightColor(jersey))
        for name in ["numberFront", "numberBack"] {
            node.childNode(withName: name, recursively: true)?
                .geometry?.firstMaterial?.diffuse.contents = texture
        }
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
        // Slightly punchier greens than real broadcast turf — the saturated
        // Madden-2000 palette.
        let tones: [UIColor] = [
            UIColor(red: 0.09, green: 0.33, blue: 0.10, alpha: 1),
            UIColor(red: 0.11, green: 0.39, blue: 0.11, alpha: 1),
            UIColor(red: 0.08, green: 0.28, blue: 0.09, alpha: 1),
            UIColor(red: 0.13, green: 0.43, blue: 0.12, alpha: 1),
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
        lightStripe.diffuse.contents = UIColor(red: 0.17, green: 0.49, blue: 0.16, alpha: 0.55)
        lightStripe.transparency = 0.55
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

    // MARK: - Stadium (night bowl + crowd + floodlights)

    /// Wraps the field in a raked night-crowd bowl with floodlight pylons,
    /// turning the surrounding void into a lit stadium — the "Sunday Night"
    /// look. Static geometry, built once. The crowd is self-lit (emissive) so
    /// it reads as a night crowd under floodlights instead of collapsing into
    /// shadow. Rises just behind the apron boards (buildApronWalls) so there is
    /// no dark moat between the field and the stands.
    private func buildStadium() {
        let stadium = SCNNode()
        stadium.name = "stadium"

        let halfW = FieldConstants.fieldWidth / 2
        let halfL = FieldConstants.totalLength / 2
        let ax = halfW + 7, az = halfL + 7
        let r: Float = 22   // corner radius → rounded-rectangle stadium ends

        // A closed loop of inner-base anchors (rounded rectangle) with an
        // outward horizontal normal per vertex; each tier is lofted by pushing
        // these anchors out along their normal and up.
        typealias Anchor = (x: Float, z: Float, nx: Float, nz: Float)
        var pts: [(Float, Float)] = []
        let centers: [(Float, Float)] = [(ax - r, az - r), (-(ax - r), az - r),
                                         (-(ax - r), -(az - r)), (ax - r, -(az - r))]
        let starts: [Float] = [0, .pi / 2, .pi, 3 * .pi / 2]
        let cornerSteps = 6
        for (i, c) in centers.enumerated() {
            for s in 0...cornerSteps {
                let a = starts[i] + (Float(s) / Float(cornerSteps)) * (.pi / 2)
                pts.append((c.0 + r * cos(a), c.1 + r * sin(a)))
            }
        }
        let n = pts.count
        var anchors: [Anchor] = []
        for i in 0..<n {
            let p = pts[i], pn = pts[(i + 1) % n], pp = pts[(i - 1 + n) % n]
            var tx = pn.0 - pp.0, tz = pn.1 - pp.1
            let tl = max(1e-4, (tx * tx + tz * tz).squareRoot()); tx /= tl; tz /= tl
            anchors.append((p.0, p.1, tz, -tx))   // rotate tangent −90° → outward normal
        }

        func tier(_ a: [Anchor], yInner: Float, yTop: Float, depth: Float,
                  uvRepeat: Float, tex: UIImage, emissive: CGFloat) -> SCNNode {
            var verts: [SCNVector3] = []; var uvs: [CGPoint] = []; var idx: [Int32] = []
            let cnt = a.count
            for i in 0..<cnt {
                let v = a[i]
                verts.append(SCNVector3(v.x, yInner, v.z))
                verts.append(SCNVector3(v.x + v.nx * depth, yTop, v.z + v.nz * depth))
                let u = CGFloat(Float(i) / Float(cnt)) * CGFloat(uvRepeat)
                uvs.append(CGPoint(x: u, y: 0)); uvs.append(CGPoint(x: u, y: 1))
            }
            for i in 0..<cnt {
                let p0 = Int32((i * 2) % (cnt * 2)), p1 = Int32((i * 2 + 1) % (cnt * 2))
                let p2 = Int32(((i + 1) * 2) % (cnt * 2)), p3 = Int32(((i + 1) * 2 + 1) % (cnt * 2))
                idx += [p0, p2, p1, p1, p2, p3]   // winding faces inward toward the field
            }
            let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts),
                                            SCNGeometrySource(textureCoordinates: uvs)],
                                  elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            let m = SCNMaterial()
            m.diffuse.contents = tex; m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.isDoubleSided = true; m.roughness.contents = 0.95; m.lightingModel = .physicallyBased
            if emissive > 0 {
                m.emission.contents = tex; m.emission.wrapS = .repeat; m.emission.wrapT = .repeat
                m.emission.intensity = emissive
            }
            geo.materials = [m]
            let node = SCNNode(geometry: geo); node.castsShadow = false
            return node
        }

        // lower bowl → upper deck → facade cap, each lofted from the previous
        // deck's outer edge so the bowl reads continuous.
        let lower = Self.crowdTexture(tint: UIColor(red: 0.20, green: 0.21, blue: 0.28, alpha: 1))
        let upper = Self.crowdTexture(tint: UIColor(red: 0.17, green: 0.18, blue: 0.25, alpha: 1))
        stadium.addChildNode(tier(anchors, yInner: 1.3, yTop: 9, depth: 20,
                                  uvRepeat: 46, tex: lower, emissive: 0.6))
        let upperA = anchors.map { Anchor(x: $0.x + $0.nx * 20, z: $0.z + $0.nz * 20, nx: $0.nx, nz: $0.nz) }
        stadium.addChildNode(tier(upperA, yInner: 9, yTop: 18, depth: 22,
                                  uvRepeat: 46, tex: upper, emissive: 0.5))
        let facadeA = upperA.map { Anchor(x: $0.x + $0.nx * 22, z: $0.z + $0.nz * 22, nx: $0.nx, nz: $0.nz) }
        let facadeTex = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor(red: 0.07, green: 0.075, blue: 0.095, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        stadium.addChildNode(tier(facadeA, yInner: 18, yTop: 21, depth: 6,
                                  uvRepeat: 1, tex: facadeTex, emissive: 0))

        // Floodlight pylons at the four corners: dark pole + a bright emissive
        // bank aimed at the field. HDR bloom gives them a night-lights halo.
        for (sx, sz): (Float, Float) in [(1, 1), (-1, 1), (-1, -1), (1, -1)] {
            let px = (ax + 5) * sx, pz = (az + 5) * sz
            let pole = SCNNode(geometry: SCNCylinder(radius: 0.5, height: 30))
            pole.geometry?.firstMaterial?.diffuse.contents = UIColor(white: 0.10, alpha: 1)
            pole.position = SCNVector3(px, 15, pz); pole.castsShadow = false
            stadium.addChildNode(pole)

            let bank = SCNNode(geometry: SCNBox(width: 9, height: 3.4, length: 0.6, chamferRadius: 0.2))
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(white: 0.9, alpha: 1)
            bm.emission.contents = UIColor(red: 1.0, green: 0.98, blue: 0.9, alpha: 1)
            bm.emission.intensity = 1.0
            bank.geometry?.firstMaterial = bm
            bank.position = SCNVector3(px * 0.9, 29, pz * 0.9)
            bank.look(at: SCNVector3(0, 0, 0)); bank.castsShadow = false
            stadium.addChildNode(bank)
        }

        rootNode.addChildNode(stadium)
    }

    /// Procedural distant-crowd texture: a mottled low-contrast speckle over a
    /// dark tint, with sparse bright points (phone screens / white shirts under
    /// lights). Tiled around each stadium tier. Built once at scene setup.
    private static func crowdTexture(tint: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            tint.setFill(); c.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0, alpha: 0.12).setFill()   // faint horizontal seat rows
            var y: CGFloat = 0
            while y < size.height { c.fill(CGRect(x: 0, y: y, width: size.width, height: 2)); y += 5 }
            // 2px speckle so the crowd survives at distance/through fog
            let dots = Int(size.width * size.height) / 9
            for _ in 0..<dots {
                let x = CGFloat(Int.random(in: 0..<256) * 2), yy = CGFloat(Int.random(in: 0..<64) * 2)
                let v = CGFloat.random(in: 0.30...0.85)
                let col = Bool.random()
                    ? UIColor(red: v, green: v * 0.88, blue: v * 0.72, alpha: 0.7)
                    : UIColor(red: v * 0.74, green: v * 0.84, blue: v, alpha: 0.7)
                col.setFill(); c.fill(CGRect(x: x, y: yy, width: 2, height: 2))
            }
            for _ in 0..<(dots / 55) {   // bright points: phone screens / white shirts under lights
                let x = CGFloat(Int.random(in: 0..<256) * 2), yy = CGFloat(Int.random(in: 0..<64) * 2)
                UIColor(white: 1.0, alpha: 0.9).setFill(); c.fill(CGRect(x: x, y: yy, width: 2, height: 2))
            }
        }
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

    // MARK: - Referee

    /// The back judge: a lightweight zebra-striped figure standing in the
    /// offensive backfield ~7 yards behind the ball, off to the side, sliding
    /// along with the LOS on every formation move (see updateMarkers). Pure
    /// dressing — no number, no blob shadow, never part of a play.
    private func buildReferee() {
        let container = SCNNode()
        container.name = "referee"

        let figure = SCNNode()
        // Leaner than the stocky players — officials don't wear pads.
        figure.scale = SCNVector3(1.02, 1.14, 1.02)
        container.addChildNode(figure)

        let stripes = SCNMaterial()
        stripes.diffuse.contents = Self.refereeStripeTexture()
        stripes.roughness.contents = 0.75

        let blackCloth = SCNMaterial()
        blackCloth.diffuse.contents = UIColor(white: 0.09, alpha: 1)
        blackCloth.roughness.contents = 0.85

        let skin = SCNMaterial()
        skin.diffuse.contents = Self.skinTones[1]
        skin.roughness.contents = 0.8

        // Legs: black slacks.
        for xSign: Float in [-1, 1] {
            let legGeometry = SCNCapsule(capRadius: 0.085, height: 0.64)
            legGeometry.radialSegmentCount = 8
            legGeometry.materials = [blackCloth]
            let leg = SCNNode(geometry: legGeometry)
            leg.position = SCNVector3(xSign * 0.13, -0.17, 0)
            figure.addChildNode(leg)
        }

        // Striped torso (stripe texture wraps the capsule vertically).
        let torsoGeometry = SCNCapsule(capRadius: 0.23, height: 0.8)
        torsoGeometry.radialSegmentCount = 10
        torsoGeometry.materials = [stripes]
        let torso = SCNNode(geometry: torsoGeometry)
        torso.position = SCNVector3(0, 0.42, 0)
        torso.scale = SCNVector3(1.05, 1.0, 0.8)
        figure.addChildNode(torso)

        // Arms resting at his sides, hinged at the shoulder (pivot at the
        // top of the capsule) so the TD/first-down signals swing correctly.
        for xSign: Float in [-1, 1] {
            let armGeometry = SCNCapsule(capRadius: 0.06, height: 0.52)
            armGeometry.radialSegmentCount = 8
            armGeometry.materials = [stripes]
            let arm = SCNNode(geometry: armGeometry)
            arm.name = xSign < 0 ? "refArmL" : "refArmR"
            arm.pivot = SCNMatrix4MakeTranslation(0, 0.26, 0)
            arm.position = SCNVector3(xSign * 0.31, 0.76, 0)
            arm.eulerAngles = SCNVector3(0, 0, xSign * -0.14)
            figure.addChildNode(arm)
        }

        // Head + white cap (the referee's hat).
        let headGeometry = SCNSphere(radius: 0.13)
        headGeometry.segmentCount = 10
        headGeometry.materials = [skin]
        let head = SCNNode(geometry: headGeometry)
        head.position = SCNVector3(0, 0.95, 0)
        figure.addChildNode(head)

        let capGeometry = SCNSphere(radius: 0.14)
        capGeometry.segmentCount = 10
        let capMaterial = SCNMaterial()
        capMaterial.diffuse.contents = UIColor(white: 0.93, alpha: 1)
        capMaterial.roughness.contents = 0.7
        capGeometry.materials = [capMaterial]
        let cap = SCNNode(geometry: capGeometry)
        cap.position = SCNVector3(0, 1.02, -0.02)
        cap.scale = SCNVector3(1, 0.62, 1)
        figure.addChildNode(cap)

        // Parked near midfield until the first marker update places him.
        container.position = SCNVector3(11, FieldConstants.playerHeight / 2, -7)
        rootNode.addChildNode(container)
        refereeNode = container
    }

    /// Vertical black-and-white stripes — wraps a capsule as the zebra shirt.
    private static func refereeStripeTexture() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.94, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.06, alpha: 1).setFill()
            for x in stride(from: 0, to: 64, by: 16) {
                ctx.fill(CGRect(x: CGFloat(x), y: 0, width: 8, height: 64))
            }
        }
    }

    /// Touchdown signal: both of the referee's arms shoot straight up, hold
    /// a beat, and drop back to his sides.
    func refereeSignalTouchdown() {
        guard let ref = refereeNode else { return }
        for (name, sign) in [("refArmL", CGFloat(-1)), ("refArmR", CGFloat(1))] {
            guard let arm = ref.childNode(withName: name, recursively: true) else { continue }
            arm.removeAction(forKey: "signal")
            let raise = SCNAction.rotateTo(x: 0, y: 0, z: sign * 2.95, duration: 0.28)
            raise.timingMode = .easeOut
            let rest = SCNAction.rotateTo(x: 0, y: 0, z: -sign * 0.14, duration: 0.35)
            rest.timingMode = .easeInEaseOut
            arm.runAction(SCNAction.sequence([raise, SCNAction.wait(duration: 1.6), rest]),
                          forKey: "signal")
        }
    }

    /// First-down signal: the referee points downfield (his facing follows
    /// the offense direction via `moveReferee`) with his right arm.
    func refereeSignalFirstDown() {
        guard let ref = refereeNode,
              let arm = ref.childNode(withName: "refArmR", recursively: true) else { return }
        arm.removeAction(forKey: "signal")
        let point = SCNAction.rotateTo(x: -1.45, y: 0, z: -0.08, duration: 0.25)
        point.timingMode = .easeOut
        let rest = SCNAction.rotateTo(x: 0, y: 0, z: -0.14, duration: 0.3)
        rest.timingMode = .easeInEaseOut
        arm.runAction(SCNAction.sequence([point, SCNAction.wait(duration: 1.1), rest]),
                      forKey: "signal")
    }

    /// Walks the referee to his spot ~7 yards behind the offense, facing the
    /// line — he trails every formation shift like the real back judge.
    private func moveReferee(losZ: Float, direction: Float) {
        guard let ref = refereeNode else { return }
        let z = max(-56, min(56, losZ - direction * 7))
        let move = SCNAction.move(to: SCNVector3(11, FieldConstants.playerHeight / 2, z),
                                  duration: 0.8)
        move.timingMode = .easeInEaseOut
        ref.runAction(move, forKey: "refMove")
        let yaw: CGFloat = direction >= 0 ? 0 : .pi
        ref.runAction(SCNAction.rotateTo(x: 0, y: yaw, z: 0, duration: 0.45,
                                         usesShortestUnitArc: true), forKey: "refFace")
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
        // applyUniform re-tints per team without cross-talk. Only SHOE
        // keeps the shared prototype material. MASK is per-figure too —
        // ~40 % of teams run a team-colored cage (uniform.facemask).
        let tints: [String: UIColor] = [
            "JERSEY": uniform.jersey,
            "PANTS": uniform.pants,
            "HELMET": uniform.helmet,
            "SKIN": Self.skinTones[number % Self.skinTones.count],
            "MASK": uniform.facemask ?? Self.facemaskGray,
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

        // Trim details share one material per slot inside the figure so
        // applyUniform re-tints stripes/socks per team in one place.
        let stripeMaterial = SCNMaterial()
        stripeMaterial.name = "STRIPE"
        stripeMaterial.diffuse.contents = Self.stripeColor(for: uniform)
        stripeMaterial.roughness.contents = 0.6
        let sockMaterial = SCNMaterial()
        sockMaterial.name = "SOCK"
        sockMaterial.diffuse.contents = Self.sockColor(for: uniform)
        sockMaterial.roughness.contents = 0.7

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

            // Sock: a team-color band above the ankle, proud of the shin so
            // it reads from the coach distance.
            let sockGeometry = SCNCylinder(radius: 0.068, height: 0.13)
            sockGeometry.radialSegmentCount = 12
            sockGeometry.materials = [sockMaterial]
            let sock = SCNNode(geometry: sockGeometry)
            sock.name = "sock"
            sock.castsShadow = false
            sock.position = SCNVector3(0, -0.25, 0)
            shin.addChildNode(sock)

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

            // Sleeve stripe: a counter-color ring around the mid upper arm —
            // low enough to clear the shoulder-pad flare in every stance.
            let stripeGeometry = SCNCylinder(radius: 0.1, height: 0.055)
            stripeGeometry.radialSegmentCount = 12
            stripeGeometry.materials = [stripeMaterial]
            let stripe = SCNNode(geometry: stripeGeometry)
            stripe.name = "sleeveStripe"
            stripe.castsShadow = false
            stripe.position = SCNVector3(0, -0.14, 0)
            arm.addChildNode(stripe)

            let forearm = instantiate(kit.forearm, name: "forearm", retint: retint)
            forearm.position = SCNVector3(0, -0.42, 0)
            forearm.eulerAngles = SCNVector3(-0.15, 0, 0)
            arm.addChildNode(forearm)

            // Hand: a skin ball capping the bare forearm.
            let handGeometry = SCNSphere(radius: 0.055)
            handGeometry.segmentCount = 10
            if let skinCopy = figureMaterials["SKIN"] {
                handGeometry.materials = [skinCopy]
            } else {
                let skinMaterial = SCNMaterial()
                skinMaterial.name = "SKIN"
                skinMaterial.diffuse.contents = Self.skinTones[number % Self.skinTones.count]
                skinMaterial.roughness.contents = 0.8
                handGeometry.materials = [skinMaterial]
            }
            let hand = SCNNode(geometry: handGeometry)
            hand.name = "hand"
            hand.castsShadow = false
            hand.position = SCNVector3(0, -0.28, 0)
            forearm.addChildNode(hand)
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
        // the whole assembly sits where the old helmet sphere was. ~8%
        // oversized — the bobblehead Madden-2000 proportion. The cage goes
        // through retint too: its per-figure MASK copy carries the optional
        // team color (uniform.facemask).
        let helmet = SCNNode()
        helmet.name = "helmet"
        helmet.position = SCNVector3(0, 1.04, 0)
        helmet.scale = SCNVector3(1.08, 1.08, 1.08)
        helmet.addChildNode(instantiate(kit.helmetShell, retint: retint))
        helmet.addChildNode(instantiate(kit.facemask, retint: retint))

        // Team-abbreviation decals on both shell sides — the classic logo
        // read. One per-figure HELMETDECAL material (applyUniform swaps the
        // texture per team); hidden while the uniform has no abbreviation
        // (the legacy quick-match path).
        let decalMaterial = SCNMaterial()
        decalMaterial.name = "HELMETDECAL"
        decalMaterial.lightingModel = .constant
        if !uniform.abbreviation.isEmpty {
            decalMaterial.diffuse.contents = Self.abbreviationTexture(
                uniform.abbreviation, darkText: Self.isLightColor(uniform.helmet))
        }
        for xSign in [Float(-1), 1] {
            let plane = SCNPlane(width: 0.19, height: 0.19)
            plane.materials = [decalMaterial]
            let decal = SCNNode(geometry: plane)
            decal.name = "helmetDecal"
            decal.castsShadow = false
            decal.position = SCNVector3(xSign * 0.19, 0.02, -0.01)
            decal.eulerAngles = SCNVector3(0, xSign * Float.pi / 2, 0)
            decal.isHidden = uniform.abbreviation.isEmpty
            helmet.addChildNode(decal)
        }
        figure.addChildNode(helmet)
    }

    // MARK: - Players

    /// Position-silhouette body builds — the coach camera reads OL vs WR
    /// instantly by trunk width. Implemented as figure/part scaling on top
    /// of the shared mesh (works identically for the kit and the procedural
    /// fallback); role slots map to types via PlayChoreographer.bodyTypes.
    enum BodyType {
        /// OL/DL: wide trunk, thick limbs, a touch shorter.
        case heavy
        /// QB/RB/LB/TE: the baseline build.
        case medium
        /// WR/DB: narrow trunk, slimmer limbs, slightly taller.
        case lean

        /// (figure height, torso width, torso depth, limb thickness)
        /// multipliers over the baseline figure.
        fileprivate var multipliers: (height: Float, torsoX: Float, torsoZ: Float, limb: Float) {
            switch self {
            case .heavy: return (0.96, 1.25, 1.20, 1.15)
            case .medium: return (1.00, 1.00, 1.00, 1.00)
            case .lean: return (1.03, 0.88, 0.92, 0.90)
            }
        }
    }

    /// Re-applies a body build to an existing player node. Absolute values
    /// (base × multiplier), so formation moves can restamp types when the
    /// same 22 nodes swap between offense and defense roles on a possession
    /// change. Only scales are touched — every hinge position, animation key
    /// and decal survives.
    private func applyBodyType(_ type: BodyType, to node: SCNNode) {
        guard let figure = node.childNode(withName: "figure", recursively: false) else { return }
        let m = type.multipliers
        // Baseline stocky Madden figure scale (see makePlayerNode).
        figure.scale = SCNVector3(1.28, 1.18 * m.height, 1.18)
        // The kit torso models its width in the mesh (base 1); the
        // procedural fallback torso carries its squash in the node scale.
        let torsoBase: SCNVector3 = Self.playerKit != nil
            ? SCNVector3(1, 1, 1)
            : SCNVector3(1.25, 1.0, 0.85)
        if let body = figure.childNode(withName: "body", recursively: false) {
            body.scale = SCNVector3(torsoBase.x * m.torsoX, torsoBase.y, torsoBase.z * m.torsoZ)
        }
        // Limb thickness: scale the top joints in x/z only — lengths and
        // child hinge offsets (y) stay exact, so the gait math is untouched.
        for name in ["leg", "legR", "arm", "armR"] {
            figure.childNode(withName: name, recursively: false)?.scale = SCNVector3(m.limb, 1, m.limb)
        }
    }

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
    /// Skeletal drivers for the Animation Overhaul path, keyed by the player's
    /// "figure" node (the same node every posing lookup already uses). Present
    /// only when `FieldConstants.useSkeletalFigures` is on.
    private var skeletalFigures: [ObjectIdentifier: SkeletalFigure] = [:]

    /// The skeletal driver behind a "figure" node, if this scene runs the
    /// skinned-mesh path for that player.
    private func skeletalDriver(for figure: SCNNode) -> SkeletalFigure? {
        skeletalFigures[ObjectIdentifier(figure)]
    }

    /// Per-frame foot-lock IK tick, called from the SCNView's render delegate
    /// (`didApplyAnimationsAtTime`) so each running figure's planted foot pins to
    /// the turf instead of sliding. Cheap: two short IK chains per skeletal
    /// figure, only engaged while a foot is in contact. Runs on the main thread
    /// (SCNView drives its render loop there), so iterating the dict is safe.
    func updateFootLocks(atTime time: TimeInterval) {
        guard !skeletalFigures.isEmpty else { return }
        for fig in skeletalFigures.values { fig.updateFootLock(atTime: time) }
    }

    private func makePlayerNode(uniform: Uniform, number: Int,
                                bodyType: BodyType = .medium) -> SCNNode {
        let container = SCNNode()
        container.name = "player_\(number)"

        let figure = SCNNode()
        figure.name = "figure"
        // Stocky Madden-2000 proportions: extra width at unchanged height —
        // the tank-like silhouette that reads from the pulled-back camera.
        // applyBodyType below layers the position build on top of this.
        figure.scale = SCNVector3(1.28, 1.18, 1.18)
        container.addChildNode(figure)

        // Blob shadow under the feet — the hard PSX-era drop shadow that
        // anchors every player to the turf.
        let shadowGeometry = SCNCylinder(radius: 0.46, height: 0.01)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.diffuse.contents = UIColor(white: 0, alpha: 0.38)
        shadowMaterial.lightingModel = .constant
        shadowGeometry.materials = [shadowMaterial]
        let shadow = SCNNode(geometry: shadowGeometry)
        shadow.name = "blobShadow"
        shadow.position = SCNVector3(0, -0.47, 0)
        shadow.castsShadow = false
        container.addChildNode(shadow)

        let skin = Self.skinTones[number % Self.skinTones.count]
        // Size + pre-snap stance by build: linemen bigger and crouched low,
        // skill players leaner and more upright.
        let bodyScale: CGFloat, stance: CGFloat
        switch bodyType {
        case .heavy:  bodyScale = 1.07; stance = 0.95
        case .medium: bodyScale = 1.0;  stance = 0.40
        case .lean:   bodyScale = 0.95; stance = 0.0
        }
        if FieldConstants.useSkeletalFigures,
           let skel = SkeletalFigure(jersey: uniform.jersey, pants: uniform.pants,
                                     helmet: uniform.helmet, skin: skin,
                                     mask: uniform.facemask ?? Self.facemaskGray,
                                     variantSeed: number, bodyScale: bodyScale, stance: stance) {
            // Skinned-mesh path: the rig is pre-proportioned, so drop the kit
            // figure's stocky non-uniform scale and let the driver pose it.
            figure.scale = SCNVector3(1, 1, 1)
            figure.addChildNode(skel.content)
            skeletalFigures[ObjectIdentifier(figure)] = skel
        } else if let kit = Self.playerKit {
            buildKitFigure(kit: kit, in: figure, uniform: uniform, number: number)
            applyBodyType(bodyType, to: container)
        } else {
            buildProceduralFigure(in: figure, uniform: uniform, number: number)
            applyBodyType(bodyType, to: container)
        }

        // Numbers printed on the jersey itself, chest and back (Madden-2000).
        if let body = figure.childNode(withName: "body", recursively: false) {
            addNumberDecals(to: body, number: number, jersey: uniform.jersey)
        }

        // Floating billboard number: now that the jersey carries the number
        // it drops to a small, dimmed long-range aid — don't remove it, it's
        // what keeps the far side of the field readable.
        let numberText = SCNText(string: "\(number)", extrusionDepth: 0.01)
        numberText.font = UIFont.systemFont(ofSize: 0.38, weight: .bold)
        numberText.flatness = 0.4

        let numberMaterial = SCNMaterial()
        numberMaterial.diffuse.contents = UIColor.white
        numberMaterial.emission.contents = UIColor(white: 0.2, alpha: 1.0)
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

        // Face the number toward the camera (angled up), dimmed so the
        // jersey decals carry the primary read. The coach shot dims it
        // further — see billboardNumberOpacity. Sits clear ABOVE the helmet
        // (top ~1.4): at the old 1.33 the digits overlapped the helmet and,
        // from the low coach angle, read as phantom chest numbers on
        // whoever stood behind.
        numberNode.eulerAngles = SCNVector3(-Float.pi / 4, 0, 0)
        numberNode.position = SCNVector3(0, 1.52, 0)
        numberNode.opacity = billboardNumberOpacity

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
        // sphere peeks out at the front. ~8% oversized (Madden-2000 head).
        helmet.scale = SCNVector3(1.08, 1.03, 1.13)
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

        // Broadcast post-processing: HDR bloom gives the floodlights and painted
        // white lines a night-lights glow; SSAO grounds the players with contact
        // shadow; a gentle vignette + saturation/contrast lift pushes the flat
        // daylight look toward a Sunday-night broadcast.
        camera.bloomThreshold = 0.75
        camera.bloomIntensity = 1.0
        camera.bloomBlurRadius = 12
        camera.saturation = 1.08
        camera.contrast = 0.10
        camera.vignettingIntensity = 0.20
        camera.vignettingPower = 1.5
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 1.0
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.wantsExposureAdaptation = false

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
        cameraLookAtConstraint = lookAtConstraint
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
        mainLight.shadowColor = UIColor(white: 0, alpha: 0.45)
        mainLight.shadowRadius = 3
        mainLight.shadowSampleCount = 16   // crisper contact shadows under floodlights
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
        fillLight.color = UIColor(red: 0.82, green: 0.86, blue: 1.0, alpha: 1.0)  // cool night fill
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
        ambientLight.color = UIColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1.0)  // cool night ambient
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
        activeWeather = weather
        rootNode.childNode(withName: "weatherEmitter", recursively: false)?.removeFromParentNode()
        rootNode.childNode(withName: "snowBlanket", recursively: false)?.removeFromParentNode()
        setLightIntensities(main: 1200, fill: 400, ambient: 500)
        applyFog(color: Self.clearFogColor, start: 70, end: 210)

        switch weather {
        case .clear, .wind, .dome:
            // Dome: indoor game, no precipitation and no gust visuals.
            break
        case .rain:
            addWeatherEmitter(Self.rainSystem(coach: currentShotStyle == .coach))
            setLightIntensities(main: 850, fill: 300, ambient: 420)
            // Pull the fog in and cool it: the far field dissolves into the
            // wet night instead of ending in a hard dark edge.
            applyFog(color: UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1), start: 65, end: 180)
        case .snow:
            addWeatherEmitter(Self.snowSystem(coach: currentShotStyle == .coach))
            addSnowBlanket()
            setLightIntensities(main: 1200, fill: 400, ambient: 620)
            // Lift the fog toward a snowy sky-glow grey so distant flakes
            // melt into the haze instead of reading as a starfield against
            // the black backdrop.
            applyFog(color: UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1), start: 62, end: 165)
        }
    }

    /// Night-sky navy that matches the app's dark backdrop; the default
    /// depth fog for clear conditions.
    private static let clearFogColor = UIColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)

    /// Sets the scene-level distance fog. Start distances stay past the play
    /// area (camera sits ~40-50 units from the action), so the fog only
    /// softens the far end of the field and whatever falls through it.
    ///
    /// The sky (scene background) is tinted to the same color: SceneKit fog
    /// does not touch particles, so without this, distant flakes render as
    /// bright stars against the near-black backdrop. Matching the backdrop
    /// to the fog both hides that and blends the field's far edge into the
    /// horizon.
    private func applyFog(color: UIColor, start: CGFloat, end: CGFloat) {
        fogColor = color
        fogStartDistance = start
        fogEndDistance = end
        fogDensityExponent = 1.4
        background.contents = color
    }

    private func setLightIntensities(main: CGFloat, fill: CGFloat, ambient: CGFloat) {
        rootNode.childNode(withName: "mainLight", recursively: false)?.light?.intensity = main
        rootNode.childNode(withName: "fillLight", recursively: false)?.light?.intensity = fill
        rootNode.childNode(withName: "ambientLight", recursively: false)?.light?.intensity = ambient
    }

    /// Height of the weather emitter node; the spawn slab straddles this
    /// (y 4-12). Low on purpose: it stays well under the broadcast cameras
    /// (y 24-33), so nothing spawns next to that lens as a giant blob, and
    /// distant flakes stay visually below the far field edge instead of
    /// dotting the dark sky like a starfield.
    ///
    /// The COACH lens (y 8.2-9.3) sits INSIDE this band, so coach shots
    /// additionally push the whole slab downfield (`weatherSlabZOffset`)
    /// and run smaller/dimmer particles (see rainSystem/snowSystem) —
    /// nothing may spawn on the near ray as a lens-filling blob.
    private static let weatherEmitterHeight: Float = 8

    /// The weather condition currently dressed on the field, so camera-style
    /// changes can re-tune the live emitter (coach vs broadcast particles).
    private var activeWeather: GameWeather = .clear

    /// How far the slab center slides downfield of the camera focus. The
    /// camera always sits on the -viewFacing side of the focus, so a
    /// +viewFacing push moves spawns away from the lens: with the coach
    /// slab (length 40, so ±20) the nearest spawn plane ends up ~10.6 units
    /// in front of the low lens instead of straddling it.
    private var weatherSlabZOffset: Float {
        currentShotStyle == .coach ? viewFacing * 12 : 0
    }

    /// Adds the particle emitter over the current camera focus. The slab is
    /// deliberately smaller than the field and follows focusCamera moves —
    /// precipitation lives where the camera looks, broadcast-style, not
    /// across the whole stadium depth. Coach shots push it downfield so no
    /// particle spawns next to the low lens (`weatherSlabZOffset`).
    private func addWeatherEmitter(_ system: SCNParticleSystem) {
        let node = SCNNode()
        node.name = "weatherEmitter"
        node.position = SCNVector3(0, Self.weatherEmitterHeight, focusZ + weatherSlabZOffset)
        node.addParticleSystem(system)
        rootNode.addChildNode(node)
    }

    /// Swaps the live emitter for one tuned to the current shot style
    /// (coach: small dim close-range particles in an offset slab; broadcast:
    /// the classic wide slab). No-op when the weather has no particles.
    /// The systems carry a warmup, so the swap doesn't blank the sky.
    private func retuneWeatherEmitter() {
        guard let node = rootNode.childNode(withName: "weatherEmitter", recursively: false) else { return }
        node.removeFromParentNode()
        switch activeWeather {
        case .rain: addWeatherEmitter(Self.rainSystem(coach: currentShotStyle == .coach))
        case .snow: addWeatherEmitter(Self.snowSystem(coach: currentShotStyle == .coach))
        case .clear, .wind, .dome: break
        }
    }

    /// Re-centers the weather slab on the camera's focus. No-op when no
    /// weather emitter is active. `z` is the raw focus/aim Z; the coach-mode
    /// downfield push is applied here unless `applyOffset` is false (the
    /// kick camera aims the slab explicitly).
    private func moveWeatherEmitter(toZ z: Float, animated: Bool, duration: TimeInterval,
                                    applyOffset: Bool = true) {
        guard let node = rootNode.childNode(withName: "weatherEmitter", recursively: false) else { return }
        let position = SCNVector3(0, Self.weatherEmitterHeight,
                                  z + (applyOffset ? weatherSlabZOffset : 0))
        if animated {
            let move = SCNAction.move(to: position, duration: duration)
            move.timingMode = .easeInEaseOut
            node.runAction(move, forKey: "focus")
        } else {
            node.removeAction(forKey: "focus")
            node.position = position
        }
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
    /// Streaks spawn in a low y 4-12 slab around the camera focus (emitter
    /// node at y 8) and die just past the turf.
    ///
    /// `coach` re-tunes for the low coach lens that sits inside that band:
    /// a smaller slab (pushed downfield by `weatherSlabZOffset`), finer and
    /// dimmer streaks, fewer of them — atmosphere, not a car wash.
    private static func rainSystem(coach: Bool) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = coach ? 170 : 240
        system.particleLifeSpan = 0.7
        system.emitterShape = SCNBox(width: coach ? 46 : 70, height: 8,
                                     length: coach ? 40 : 70, chamferRadius: 0)
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, -1, 0)
        system.spreadingAngle = 2
        system.particleVelocity = 24
        system.particleVelocityVariation = 6
        system.particleImage = rainStreakImage()
        system.particleSize = coach ? 0.06 : 0.2
        system.particleSizeVariation = coach ? 0.02 : 0.08
        system.particleColor = UIColor(red: 0.65, green: 0.72, blue: 0.85,
                                       alpha: coach ? 0.11 : 0.22)
        system.blendMode = .additive
        // Streak length ≈ velocity × stretch: at the low coach lens the
        // broadcast 0.06 (≈1.4 yd) reads as glowing player-height pillars
        // between the bodies — 0.022 keeps them at ~0.5 yd drizzle lines.
        system.stretchFactor = coach ? 0.022 : 0.06
        system.isLightingEnabled = false
        // Pre-roll so setWeather/retuneWeatherEmitter never shows a dry sky.
        system.warmupDuration = 1
        return system
    }

    /// Procedural snow: slow, drifting white flakes. Flakes spawn in a low
    /// y 4-12 slab around the camera focus (emitter node at y 8) — far below
    /// the broadcast camera band — so they read against the turf, not as a
    /// starfield hanging in the dark sky.
    ///
    /// `coach` re-tunes for the low coach lens that sits inside that band:
    /// a smaller slab (pushed downfield by `weatherSlabZOffset`) and small,
    /// faint flakes — the old 0.15 flakes read as head-sized white balls
    /// between the players at coach distance.
    private static func snowSystem(coach: Bool) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = coach ? 80 : 130
        system.particleLifeSpan = 8
        system.emitterShape = SCNBox(width: coach ? 46 : 70, height: 8,
                                     length: coach ? 40 : 70, chamferRadius: 0)
        system.birthLocation = .volume
        system.emittingDirection = SCNVector3(0, -1, 0)
        system.spreadingAngle = 14
        system.particleVelocity = 2.4
        system.particleVelocityVariation = 0.8
        system.particleImage = snowflakeImage()
        system.particleSize = coach ? 0.09 : 0.15
        system.particleSizeVariation = coach ? 0.03 : 0.05
        system.particleColor = UIColor(white: 1.0, alpha: coach ? 0.45 : 0.62)
        system.isLightingEnabled = false
        // Pre-roll so setWeather/retuneWeatherEmitter never shows an empty sky.
        system.warmupDuration = 5
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
