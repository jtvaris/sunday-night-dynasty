import Foundation
import SceneKit
import UIKit

/// Skeletal (skinned-mesh) coach-mode player — the Animation Overhaul Option-A
/// substrate (docs/ANIMATION_OVERHAUL_PLAN.md, Phase 0/1). Loads a rigged USD
/// character (`PlayerRig.usdc`) + a library of skeletal clips
/// (`PlayerClip_*.usdc`) and drives locomotion/actions by playing skeletal
/// animation clips instead of hand-rotating joint nodes. It slots UNDER the
/// existing "figure" node behind `FieldConstants.useSkeletalFigures`, so every
/// downstream `childNode("figure")` lookup and the container move/facing keep
/// working; only the per-limb POSING layer changes.
///
/// The Blender→USD→SceneKit pipeline and every gotcha below were proven headless
/// in the Phase 0 spike (see the reference_scenekit_skeletal_pipeline memory):
///  • Blender exports Z-up; SceneKit's `.convertToYUp` rotates the bind pose but
///    NOT the animation channels, so we load Z-up (consistent) and stand the
///    figure up with a −90° X wrapper instead.
///  • A clip's animation retargets onto any character by BONE NAME — attach it
///    to the character's `skinner.skeleton` node (NOT the armature object node),
///    on the default SYSTEM time base, and it drives that skeleton.
///  • Bone "Foo.L" in Blender exports as "Foo_L".
final class SkeletalFigure {

    // MARK: Tunables (scene units; figure origin sits at world y = playerHeight/2)
    /// Uniform scale of the Mixamo-rigged rig (~1.9 units tall, feet at y=0) down
    /// to the coach figure's on-screen size (~1.6 units).
    static let scale: CGFloat = 0.86
    /// Drop so the rig's feet (local y≈0) land on the turf (world y=0): the
    /// container sits at world y = 0.5, so −0.5 puts the soles on the ground.
    static let yOffset: CGFloat = -0.5

    // MARK: Shared, cached assets
    private static var cachedRigURL: URL?? = nil
    private static var clipCache: [String: CAAnimation] = [:]

    /// The clip names shipped in Resources (PlayerClip_<name>.usdc). Most map to
    /// the Studio Ochi football mocap; `juke` is a Mixamo dodge retargeted onto
    /// the same Metarig (tools/asset-pipeline/mixamo_retarget.py).
    static let clipNames = ["run", "idle", "sprint", "tackle", "throw", "catch", "kick", "juke", "celebrate",
                            // per-position pre-snap stances (held; played by applyStance)
                            "stance3", "stance2", "stanceSplit", "stanceUC", "stanceUpright",
                            "fall_back"]   // big-hit backward knockdown (forward falls reuse tackle_a/b)

    /// One-shot action clips retargeted from Mixamo carry a long lead-in/hold
    /// (throw 7.7s, tackle 5s, celebrate 4.5s) around a brief action beat; played
    /// at natural speed they drag. Compress each to a target on-screen duration so
    /// the beat lands in a football-appropriate window. Clips not listed play at
    /// natural speed (e.g. the Ochi kick).
    private static let actionTargetDuration: [String: TimeInterval] = [
        // tackle clips play FAST — a football hit drops the man in ~0.5-0.8s, not a
        // 2.2s slow-motion flop (the old target left everyone standing then sinking).
        "throw": 2.2, "catch": 1.6, "tackle": 1.0, "tackled": 0.85, "juke": 0.75, "celebrate": 3.0,
        "kick": 1.5, "dive": 1.6,
    ]

    /// Variety pools: an action name resolves to one of several real football-mocap
    /// variants (retargeted from the 21-clip pack, trimmed to their action window and
    /// rebased in-place — tools/asset-pipeline/pack_segments.json). Picking a fresh
    /// variant each time keeps catches/tackles/throws from looking identical. An action
    /// with no pool loads PlayerClip_<name>.usdc directly (run/idle/sprint/kick).
    /// Pools mix BOTH sources: the 21-clip pack AND Ochi's own action mocap
    /// (catch_d = Ochi Catch-and-Fall, throw_c = Ochi Throw 01) for maximum variety.
    static let variantPools: [String: [String]] = [
        "catch":     ["catch_a", "catch_b", "catch_c", "catch_d"],  // secure / jump / dive / catch-and-fall(Ochi)
        "tackle":    ["tackle_a"],                                  // diving tackle — the man MAKING the hit lays out
        "tackled":   ["tackle_b"],                                  // getting hit / brought down — the man going DOWN
        "throw":     ["throw_a", "throw_b", "throw_c"],             // pack ×2 + Ochi Throw 01
        "celebrate": ["celeb_a", "celeb_b"],                       // spike / arms-up
        "juke":      ["juke_a"],
        "kick":      ["kick_a", "kick_b"],                          // pack punt / Ochi kickoff
    ]
    /// Last variant played per action on THIS figure, so back-to-back plays don't
    /// repeat the same clip (variety reads best when consecutive actions differ).
    private var lastVariant: [String: String] = [:]

    /// Fraction of each clip at which its "beat" lands — the catch grab, the throw
    /// release, the tackle contact. Measured headless (scratchpad/measure_hit.swift:
    /// hands-peak for catch, throwing-hand for throw, forward-reach for tackle), then
    /// sanity-adjusted (a diving catch grabs mid-reach, not at the early arm-raise).
    /// `play(action:landAfter:)` uses it to delay the clip so the beat coincides with
    /// a game event (the ball's arrival). Default 0.5 for anything unlisted.
    private static let actionHitFraction: [String: Double] = [
        "catch_a": 0.66, "catch_b": 0.70, "catch_c": 0.35, "catch_d": 0.32,
        "throw_a": 0.55, "throw_b": 0.55, "throw_c": 0.39,
        "tackle_a": 0.80, "tackle_b": 0.60,
        "kick_a": 0.50, "kick_b": 0.50,   // foot through the ball ~mid-swing
        "dive": 0.35,
    ]

    /// Whether the rig asset is present — the scene uses this to decide if the
    /// skeletal path is even available before flipping figures over.
    static var isAvailable: Bool { rigURL != nil }

    private static var rigURL: URL? {
        if let cached = cachedRigURL { return cached }
        // .usdz first (packages the character's texture), else .usdc.
        let url = Bundle.main.url(forResource: "PlayerRig", withExtension: "usdz")
            ?? Bundle.main.url(forResource: "PlayerRig", withExtension: "usdc")
        cachedRigURL = .some(url)
        if url == nil { print("SkeletalFigure: PlayerRig.usd[z|c] not in bundle — skeletal path off") }
        return url
    }

    /// Load a clip once and cache its retargetable CAAnimation. Loaded Z-up to
    /// stay in the same space as the character (see class note).
    private static func clip(_ name: String) -> CAAnimation? {
        if let c = clipCache[name] { return c }
        guard let url = Bundle.main.url(forResource: "PlayerClip_\(name)", withExtension: "usdc"),
              let scene = try? SCNScene(url: url, options: [.convertToYUp: false]),
              let animNode = firstNode(in: scene.rootNode, where: { !$0.animationKeys.isEmpty }),
              let key = animNode.animationKeys.first,
              let player = animNode.animationPlayer(forKey: key) else {
            print("SkeletalFigure: clip '\(name)' failed to load")
            return nil
        }
        let ca = CAAnimation(scnAnimation: player.animation)
        clipCache[name] = ca
        return ca
    }

    // MARK: Instance
    /// Add this under the "figure" node. Holds the standup/scale wrapper + rig.
    let content: SCNNode
    /// The skinner.skeleton node — clips attach here to drive the bones.
    private let skeleton: SCNNode

    /// Locomotion state machine. A single "run" clip covers every forward speed
    /// via stride-sync (playback matched to ground travel); backpedal reverse-
    /// plays it; idle freezes it. `nil` until the first setMoving so the initial
    /// idle is always applied.
    private enum Loco: Equatable { case idle, run, backpedal }
    private var loco: Loco? = nil

    /// Per-player phase offset into the loco cycle so a squad never steps in
    /// lockstep. NOTE: we deliberately do NOT jitter the cadence (speed) — that
    /// would desync the feet from ground travel and reintroduce foot-slide.
    /// Only the phase is jittered; the cadence is exact.
    private let phase01: CGFloat
    /// Total on-screen scale of the rig (Self.scale · bodyScale · sizeJitter).
    /// Converts the clip's native stride speed to world units so playback can be
    /// matched to ground speed. See `locoClipSpeed`.
    private let figureScale: CGFloat
    /// Which frame of the "Hold" clip to freeze on for the pre-snap idle
    /// (0 = upright, ~0.45 = deep crouch) — varies the stance by build + player.
    private let idleFraction: CGFloat

    /// The run clip's measured "treadmill speed": native units/sec of ground the
    /// planted-foot stride covers at clip speed 1.0. Measured headless with
    /// scratchpad/rig_inspect.swift (integrate the planted foot's backward travel
    /// over the clip ÷ duration → 3.716 u/s over ~8 cycles). worldStrideSpeed =
    /// runV0 · figureScale; clipSpeed = groundSpeed / worldStrideSpeed.
    private static let runV0: Float = 3.716

    // MARK: Foot-lock IK
    /// Clip-speed matching alone leaves a ~44% residual foot-slide (a run has
    /// flight phases, so the planted foot's backward speed ≠ the cycle average —
    /// measured in scratchpad/slide_test.swift). True foot-lock pins each planted
    /// foot to its contact point in world space with an `SCNIKConstraint` while
    /// the body moves over it, then releases for the swing. Driven per-frame from
    /// the scene's `didApplyAnimationsAtTime` hook (pose is animated, constraints
    /// not yet applied — so the animated foot height reads clean for plant
    /// detection). Verified in scratchpad/ik_test.swift: foot holds within ~1 cm.
    private struct FootLock {
        let bone: SCNNode          // ankle (IK effector)
        let ik: SCNIKConstraint
        var planted = false
        var lockPos = SCNVector3Zero
        var influence: Float = 0
        var minY: Float = .greatestFiniteMagnitude   // adaptive contact band
        var maxY: Float = -.greatestFiniteMagnitude
    }
    private var feet: [FootLock] = []
    private var lastLockTime: TimeInterval = 0
    /// The container's horizontal position last frame + a smoothed ground speed,
    /// so the run cadence tracks how fast the body ACTUALLY travels (not the fixed
    /// average set at `setMoving`). A stopped container → the legs settle instead
    /// of churning in place.
    private var lastContainerXZ: (x: Float, z: Float)?
    private var groundSpeedEMA: Float = 0
    /// Every bone node in the rig, cached once. The ground clamp in
    /// `updateFootLock` scans these to find the lowest joint while a fall/dive/
    /// tackle pose plays — the part that pokes through the turf is usually a leaf
    /// (a toe or fingertip), not the pelvis, so we can't clamp the root alone.
    private var groundBones: [SCNNode] = []
    /// The two hand joints, cached once. A carried ball is pinned to these so it
    /// rides the animated hands (a dropback carry) instead of a fixed belt offset.
    private var handBoneL: SCNNode?
    private var handBoneR: SCNNode?
    /// Lower-torso joint, cached once. A tucked ball rides this DOWN through a
    /// tackle so it goes to the turf with the carrier instead of being left at the
    /// tackle spot as the fall lunges the body past a container-pinned ball.
    private var tuckBone: SCNNode?

    /// Builds one skinned player. `variantSeed` (e.g. jersey number) gives each
    /// player a stable, distinct gait phase, cadence + a touch of size variation;
    /// `bodyScale` sizes by position (linemen bigger, skill players leaner).
    /// Returns nil if the rig asset is missing, so callers can fall back.
    init?(jersey: UIColor, pants: UIColor, helmet: UIColor, skin: UIColor, mask: UIColor,
          variantSeed: Int = 0, bodyScale: CGFloat = 1.0, stance: CGFloat = 0) {
        // Deterministic 0..1 hashes from the seed (no RNG — stable per player).
        let h1 = (variantSeed &* 2654435761) & 0xffff
        let h2 = (variantSeed &* 40503 &+ 12345) & 0xffff
        let h3 = (variantSeed &* 2246822519 &+ 374761) & 0xffff
        let h4 = (variantSeed &* 3266489917 &+ 668265263) & 0xffff
        self.phase01 = CGFloat(h1) / 65535.0
        let sizeJitter = 0.97 + CGFloat(h3) / 65535.0 * 0.06     // 0.97–1.03
        // Stance (0 upright → 1 crouched) sets the frozen idle frame; a small
        // per-player jitter keeps a whole line from holding an identical pose.
        let stanceJitter = (CGFloat(h4) / 65535.0 - 0.5) * 0.05
        // Keep the frozen frame in the SHALLOW part of the "Hold" clip (0 =
        // upright, ~0.16 = a light athletic crouch). The deeper frames are a
        // bent-double reach — reads as picking the ball up, not a stance.
        self.idleFraction = max(0, min(0.17, stance * 0.16 + stanceJitter))
        // A few degrees of facing jitter so the line isn't robotically parallel.
        let facingYaw = Float(CGFloat(h2) / 65535.0 - 0.5) * 0.14   // ±~4°
        guard let url = Self.rigURL,
              let scene = try? SCNScene(url: url, options: [.convertToYUp: false]),
              let skinnerNode = Self.firstNode(in: scene.rootNode, where: { $0.skinner != nil }),
              let skel = skinnerNode.skinner?.skeleton else {
            return nil
        }

        // Stand the Z-up rig up so it matches the kit convention: local +Z =
        // FRONT (downfield), which the container's yaw then orients per team.
        // The Studio Ochi rig faces +Z after just the −90° X standup (verified by
        // render), so NO extra facing flip — a 180° flip pointed everyone the
        // wrong way relative to the offense/defense direction. Reparent ALL
        // loaded content (robust to any rig source) under standup.
        let standup = SCNNode(); standup.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        for child in scene.rootNode.childNodes {
            child.removeFromParentNode()
            standup.addChildNode(child)
        }
        let face = SCNNode()   // identity: rig already faces +Z after standup
        face.addChildNode(standup)
        let wrapper = SCNNode()
        wrapper.name = "skeletal"
        let s = Self.scale * bodyScale * sizeJitter
        wrapper.scale = SCNVector3(s, s, s)
        wrapper.position = SCNVector3(0, Self.yOffset, 0)
        wrapper.eulerAngles = SCNVector3(0, facingYaw, 0)   // slight per-player facing
        wrapper.addChildNode(face)

        self.content = wrapper
        self.skeleton = skel
        self.figureScale = s
        applyUniform(jersey: jersey)
        setupFootLocks()
        setMoving(false, speed: 0)   // idle by default
    }

    // MARK: Team uniforms
    // The Studio Ochi pack ships 6 uniform textures (one UV atlas, different
    // colors). Pick the one nearest the team's jersey color so the two teams on
    // the field read as distinct and roughly match their real colors.
    private static let uniformColors: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.13, 0.32, 0.72),  // 0  blue      (Athletes 01)
        (0.00, 0.70, 0.70),  // 1  teal      (Athletes 02)
        (0.05, 0.42, 0.16),  // 2  green     (Athletes 03)
        (0.18, 0.18, 0.20),  // 3  graphite  (Athletes 04)
        (0.72, 0.12, 0.20),  // 4  red       (Athletes 05)
        (0.42, 0.68, 0.08),  // 5  lime      (Athletes 06)
    ]
    private static var uniformImageCache: [Int: UIImage] = [:]

    private static func nearestUniformIndex(to color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var best = 0, bestD = CGFloat.greatestFiniteMagnitude
        for (i, c) in uniformColors.enumerated() {
            let d = (r - c.r) * (r - c.r) + (g - c.g) * (g - c.g) + (b - c.b) * (b - c.b)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }
    private static func uniformImage(_ idx: Int) -> UIImage? {
        if let img = uniformImageCache[idx] { return img }
        guard let url = Bundle.main.url(forResource: "uniform_\(idx)", withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        uniformImageCache[idx] = img
        return img
    }

    /// Dress the player in the team uniform whose color is nearest the jersey.
    /// Swaps the whole textured atlas, so helmet/pads/pants/number all change.
    func applyUniform(jersey: UIColor) {
        guard let img = Self.uniformImage(Self.nearestUniformIndex(to: jersey)) else { return }
        Self.forEachGeometry(in: content) { geometry in
            for material in geometry.materials {
                material.diffuse.contents = img
            }
        }
    }

    // MARK: Driving
    private func clipName(for l: Loco) -> String {
        switch l {
        case .idle: return "idle"
        case .run, .backpedal: return "run"   // backpedal reverse-plays the run clip
        }
    }
    private func animKey(for l: Loco) -> String { "loco_\(l)" }

    /// Locomotion state machine. Forward motion (`run`) and backpedal both use the
    /// one run clip; idle freezes the "Hold" pose. Playback is stride-synced to
    /// ground speed so the feet track the turf instead of sliding, and state
    /// changes cross-fade. `speed` is world yd/s (the container's ground speed).
    func setMoving(_ moving: Bool, speed: Float, backpedal: Bool = false) {
        // A tackled figure holds the ground pose (key "fall"); only ACTIVE motion
        // (getting up to run/backpedal) clears it. Going IDLE must NOT stand a
        // tackled man up — otherwise a tackle beat that also slides the carrier
        // (drag-down / big-hit / shoestring) pops him back to his feet when that
        // slide's trailing idle-reset fires ~0.3-0.45s later.
        if moving {
            skeleton.removeAnimation(forKey: "fall", blendOutDuration: 0.15)
            // The snap breaks the pre-snap pose: blend the held stance OUT over a
            // beat so the man RISES smoothly out of his crouch into the run rather
            // than snapping upright (a "jump" to standing).
            skeleton.removeAnimation(forKey: "stance", blendOutDuration: 0.3)
        }
        let want: Loco = moving ? (backpedal ? .backpedal : .run) : .idle
        if let cur = loco, cur == want {
            if moving { setLocoSpeed(speed) }
            return
        }
        let prev = loco
        loco = want
        // Cross into the new state with a real blend; remove the previous so they
        // don't stack (its fade-out overlaps this one's fade-in = a transition).
        // Longer crossfades read as smooth transitions (idle↔run↔backpedal) —
        // SceneKit has no true blend tree, so a generous overlapping fade is how
        // we hide the state change instead of snapping.
        if let prev = prev { skeleton.removeAnimation(forKey: animKey(for: prev), blendOutDuration: 0.32) }
        guard let base = Self.clip(clipName(for: want))?.copy() as? CAAnimation else { return }
        base.repeatCount = .infinity
        base.fadeInDuration = 0.32
        base.fadeOutDuration = 0.32
        if moving {
            base.timeOffset = phase01 * base.duration   // desync the squad's gait phase
            base.speed = locoClipSpeed(speed, backpedal: backpedal)
        } else {
            // Idle: the Studio Ochi "Hold" clip is a crouch cycle — looping it
            // makes the squad squat up and down. Freeze it on a per-player frame
            // (idleFraction) so builds hold varied stances instead of one pose.
            base.speed = 0
            base.timeOffset = idleFraction * base.duration
        }
        skeleton.addAnimation(base, forKey: animKey(for: want))
    }

    private func setLocoSpeed(_ speed: Float) {
        guard let cur = loco, let anim = skeleton.animationPlayer(forKey: animKey(for: cur)) else { return }
        anim.speed = CGFloat(locoClipSpeed(speed, backpedal: cur == .backpedal))
    }

    /// Playback rate that matches the planted-foot cadence to ground travel, so
    /// the feet plant on the turf instead of skating: clipSpeed = groundSpeed ÷
    /// worldStrideSpeed, where worldStrideSpeed = V0 · figureScale. This is the
    /// core foot-slide fix — one exact ratio holds at every speed (the old
    /// `speed·0.28` guess plus a [0.7,2.4] clamp both mismatched and skated).
    /// Backpedal reverse-plays the run clip (negative) so the legs drive backward.
    private func locoClipSpeed(_ groundSpeed: Float, backpedal: Bool) -> Float {
        let worldStride = Self.runV0 * Float(figureScale)
        // No hard floor: a stopped container drives the cadence to ~0 so the legs
        // come to rest instead of churning in place (the per-frame ground speed in
        // updateFootLock feeds this). Still capped so a sprint never over-spins.
        let k = max(0.0, min(3.0, groundSpeed / max(0.01, worldStride)))
        return backpedal ? -k : k
    }

    // MARK: Foot-lock IK
    /// Attach an `SCNIKConstraint` to each ankle (chain root = thigh → a 2-bone
    /// thigh/shin chain). Influence starts at 0; `updateFootLock` ramps it while a
    /// foot is planted.
    private func setupFootLocks() {
        func bone(_ n: String) -> SCNNode? {
            Self.firstNode(in: skeleton, where: { ($0.name ?? "").lowercased() == n })
        }
        for (t, ft) in [("thigh_l", "foot_l"), ("thigh_r", "foot_r")] {
            guard let thigh = bone(t), let foot = bone(ft) else { continue }
            let ik = SCNIKConstraint(chainRootNode: thigh)   // 2-bone chain: thigh → shin → foot
            ik.influenceFactor = 0
            foot.constraints = [ik]
            feet.append(FootLock(bone: foot, ik: ik))
        }
        handBoneL = bone("hand_l")
        handBoneR = bone("hand_r")
        tuckBone = bone("spine_001") ?? bone("spine")
        // Cache every bone (incl. toe/finger leaf tips) for the ground clamp.
        func collectBones(_ n: SCNNode) { groundBones.append(n); n.childNodes.forEach(collectBones) }
        collectBones(skeleton)
    }

    /// Per-frame foot-lock. Call from the renderer's `didApplyAnimationsAtTime`
    /// so the animated (pre-constraint) foot height reads clean. Only engages
    /// while running/backpedaling; idle and one-shot actions keep the feet free.
    ///
    /// Proximity-damped design (pop-free by construction): on contact the foot
    /// pins to its landing point at full strength; as the body carries the
    /// animated foot away from that point, the lock strength fades with the
    /// divergence and is fully released before the foot has drifted far. So the
    /// IK cancels the slide over the first, most-visible part of the stance and
    /// then hands smoothly back to the swing — it can only ever *reduce* motion,
    /// never yank the foot to a far target (which is what would read as a pop).
    func updateFootLock(atTime time: TimeInterval) {
        guard !feet.isEmpty else { return }
        let dt: Float = lastLockTime > 0 ? Float(min(0.1, max(0.001, time - lastLockTime))) : 1.0 / 60
        lastLockTime = time

        // Drive the run cadence from the container's ACTUAL per-frame ground speed
        // instead of the fixed average set once at `setMoving`. When the body has
        // stopped — arrived at its spot, or bridging a gap between chained steps
        // under the idle grace — the legs settle to a near-stop rather than churning
        // in place; a slow move no longer over-strides into a skate either. Only
        // while genuinely in a run/backpedal loco (not a held pose).
        if loco == .run || loco == .backpedal {
            let wp = content.presentation.worldPosition
            if let last = lastContainerXZ {
                let inst = hypotf(Float(wp.x) - last.x, Float(wp.z) - last.z) / dt   // world units / s
                groundSpeedEMA += (inst - groundSpeedEMA) * min(1, 14 * dt)          // low-pass
                setLocoSpeed(groundSpeedEMA)
            }
            lastContainerXZ = (Float(wp.x), Float(wp.z))
        } else {
            lastContainerXZ = nil
            groundSpeedEMA = 0
        }

        // Foot-lock is off during ANY one-shot clip (the feet leave the turf); the
        // ground clamp below fires only for a HELD ground pose (isGrounded), never an
        // upright action (juke / standing catch / throw) — clamping those would pop
        // the whole body UP on a transient below-turf foot, reading as a mid-run jump.
        let active = (loco == .run || loco == .backpedal) && !isPosing
        let ampGate = 0.06 * Float(figureScale)      // need real gait amplitude before locking
        let maxDrift = 0.34 * Float(figureScale)     // lock strength reaches 0 by this divergence

        for i in feet.indices {
            var f = feet[i]
            let p = f.bone.presentation.worldPosition
            let y = p.y
            // adaptive contact band: chase the observed min/max, relaxing slowly
            f.minY = min(f.minY, y) + (y > f.minY ? (y - f.minY) * 0.003 : 0)
            f.maxY = max(f.maxY, y) + (y < f.maxY ? (y - f.maxY) * 0.003 : 0)
            let range = f.maxY - f.minY
            let plantThresh = f.minY + 0.20 * range
            let releaseThresh = f.minY + 0.48 * range

            var target: Float = 0
            if active && range > ampGate {
                if !f.planted {
                    if y < plantThresh { f.planted = true; f.lockPos = p }   // landing point
                } else if y > releaseThresh {
                    f.planted = false                                        // foot has lifted
                }
                if f.planted {
                    // strength fades with how far the animated foot has diverged
                    // from the landing point — full lock at contact, smooth handoff.
                    let dx = p.x - f.lockPos.x, dy = p.y - f.lockPos.y, dz = p.z - f.lockPos.z
                    let drift = (dx * dx + dy * dy + dz * dz).squareRoot()
                    target = max(0, 1 - drift / maxDrift)
                }
            } else {
                f.planted = false
            }

            // ramp toward the target strength (smooths engage + the last handoff)
            let rate: Float = 20
            if f.influence < target { f.influence = min(target, f.influence + rate * dt) }
            else { f.influence = max(target, f.influence - rate * dt) }

            if f.influence > 0.001 { f.ik.targetPosition = f.lockPos }
            f.ik.influenceFactor = CGFloat(f.influence)
            feet[i] = f
        }

        // Ground clamp. Action clips are rebased IN-PLACE (only their START is zeroed
        // — tools/asset-pipeline/rokoko_retarget.py), so a fall/dive/tackle's downward
        // travel drives a leaf joint (a toe or fingertip — NOT the pelvis, which stays
        // up) below the turf: measured up to ~0.30 m under on the diving clips. While a
        // pose plays, lift the whole rig so its lowest bone never sinks under the ground
        // plane (rest feet sit at world y ≈ 0); ease back to the rest offset once the
        // pose clears. Only a HELD ground pose (isGrounded) lifts — running/idle and
        // UPRIGHT actions (juke/catch/throw) are exempt, so a juke's foot dipping a
        // touch below the plane never pops the whole body up (that read as a mid-run jump).
        // NOTE: on iOS SCNVector3 components are Float, so keep all of this in Float.
        let restY = Float(Self.yOffset)
        if isGrounded {
            var lowest: Float = .greatestFiniteMagnitude
            for b in groundBones { lowest = min(lowest, b.presentation.worldPosition.y) }
            if lowest < -0.005 { content.position.y += -lowest }   // one-frame settle, then stable
        } else if content.position.y != restY {
            let k = min(1, 10 * dt)
            content.position.y += (restY - content.position.y) * k
            if abs(content.position.y - restY) < 0.002 { content.position.y = restY }
        }
    }

    /// True while a HELD ground pose plays (tackle / diving catch / pylon dive —
    /// all `hold:true`, key "fall"): the body is down on the turf. The ground clamp
    /// keys off THIS so it only ever lifts a genuine fall, never an upright action.
    var isGrounded: Bool { skeleton.animationPlayer(forKey: "fall") != nil }

    /// True while any one-shot clip plays — a held ground pose (above) OR an UPRIGHT
    /// action (juke / standing catch / throw / kick, key "action").
    var isPosing: Bool {
        isGrounded || skeleton.animationPlayer(forKey: "action") != nil
            || skeleton.animationPlayer(forKey: "stance") != nil
    }

    /// Immediately drop a held ground pose / action clip and fall back to the
    /// locomotion underneath. Used by a full reset (play cancel) so a downed skinned
    /// man never carries his fall pose into the next snap. A `setMoving(true)` also
    /// clears the fall, but a reset can run before any move does.
    func clearPose() {
        skeleton.removeAnimation(forKey: "fall", blendOutDuration: 0.1)
        skeleton.removeAnimation(forKey: "action", blendOutDuration: 0.1)
        skeleton.removeAnimation(forKey: "stance", blendOutDuration: 0.1)
    }

    /// Wipe ALL animation/clamp/foot-lock state and re-establish a clean idle. The
    /// 22 figures are REUSED across every play; without a hard reset between plays,
    /// stale animation players (spent one-shot clips, fading crossfades, a held
    /// pose) accumulate on the skeleton and, from the SECOND play on, blend into the
    /// live locomotion as brief full-body collapses ("player dives mid-run"). Called
    /// from `resetGait` at each snap (`cancelPlay`), so every play starts from a
    /// known-clean rig. A soft `clearPose` is not enough — the residue is whole
    /// animation players, so we `removeAllAnimations` and rebuild the idle.
    func fullReset(blendOut: TimeInterval = 0) {
        // `blendOut > 0` fades the current pose out over a beat instead of snapping
        // to the rest rig — at the snap this is what makes a lineman RISE out of his
        // held stance into the play rather than popping upright with no animation.
        // Spent players are still removed (just faded), so no residue accumulates.
        if blendOut > 0 {
            skeleton.removeAllAnimations(withBlendOutDuration: CGFloat(blendOut))
        } else {
            skeleton.removeAllAnimations()
        }
        loco = nil
        content.position = SCNVector3(0, Float(Self.yOffset), 0)
        for i in feet.indices {
            feet[i].planted = false
            feet[i].influence = 0
            feet[i].ik.influenceFactor = 0
            feet[i].minY = .greatestFiniteMagnitude
            feet[i].maxY = -.greatestFiniteMagnitude
        }
        lastLockTime = 0
        setMoving(false, speed: 0)
    }

    /// World position to pin a carried ball to, tracking the animated body so the
    /// ball stays with the player instead of floating at the fixed belt offset
    /// `attachBall` uses (that offset is calibrated for the procedural-kit arm
    /// nodes, which the skinned rig lacks). `chest` → midpoint of both hands (a QB
    /// two-hand dropback carry); otherwise the lower torso (a tuck rides the body
    /// DOWN through a tackle). nil if the rig lacks the joints. Uses `presentation`
    /// so it reflects the current animated pose.
    func ballCarryWorldPosition(chest: Bool) -> SCNVector3? {
        if chest {
            guard let r = handBoneR?.presentation.worldPosition else {
                return handBoneL?.presentation.worldPosition
            }
            guard let l = handBoneL?.presentation.worldPosition else { return r }
            return SCNVector3((l.x + r.x) * 0.5, (l.y + r.y) * 0.5, (l.z + r.z) * 0.5)
        }
        return tuckBone?.presentation.worldPosition
    }

    /// Fire a one-shot action clip (catch/tackle/throw…) over the locomotion.
    /// `delay` starts it later (sync a catch to the ball's arrival); `hold`
    /// keeps the final frame (a tackled man stays on the turf until he moves).
    /// `landAfter` (when set) times the clip so its beat — the catch/throw/tackle
    /// moment — lands at that time from now (e.g. the ball's arrival), regardless of
    /// which variant was picked. This replaces the old fixed per-action delay, which
    /// broke once one action could resolve to variants that peak at different frames.
    /// `beatAt` compresses the clip so its beat (the throw release) lands exactly that
    /// many seconds after it starts — used to sync the QB's release to the ball leaving
    /// his hand, regardless of which throw variant was picked. Takes precedence over the
    /// default duration compression. Mutually exclusive with `landAfter`.
    func play(action name: String, delay: TimeInterval = 0, landAfter: TimeInterval? = nil,
              beatAt: TimeInterval? = nil, hold: Bool = false) {
        let variant = pickVariant(for: name)
        guard let base = Self.clip(variant)?.copy() as? CAAnimation else { return }
        base.repeatCount = 1
        let hitFrac = Self.actionHitFraction[variant] ?? 0.5
        if let beat = beatAt, beat > 0.01, base.duration > 0.01 {
            base.speed = Float(max(0.5, base.duration * hitFrac / beat))   // release lands at `beat`
        } else if let target = Self.actionTargetDuration[name], base.duration > 0.01 {
            // Compress long clips to a football-appropriate beat; the pack variants are
            // already trimmed, so only ever speed UP (never slow into sluggish slow-mo).
            base.speed = Float(max(1.0, base.duration / target))
        }
        // Sync the beat to a game event: delay so hitFraction·playedDuration == landAfter.
        var startDelay = delay
        if let land = landAfter {
            let playedDur = base.duration / Double(max(0.01, base.speed))
            startDelay = max(0, land - hitFrac * playedDur)
        }
        base.fadeInDuration = 0.2       // smoother blend from the run into the action
        base.fadeOutDuration = hold ? 0 : 0.3
        base.isRemovedOnCompletion = !hold
        if hold { base.fillMode = .forwards }
        if startDelay > 0 { base.beginTime = CACurrentMediaTime() + startDelay }
        skeleton.addAnimation(base, forKey: hold ? "fall" : "action")
    }

    /// Ease into a held pre-snap STANCE clip (three-point / two-point / receiver
    /// split / QB under-center / upright) and hold the final frame until the snap.
    /// Unlike a fall this does NOT count as grounded — no ground clamp fires (the
    /// pose keeps the down hand just above the turf), but it IS `isPosing`, so
    /// foot-lock is suspended (the pose plants the feet). `setMoving(true)` clears
    /// it on takeoff. Loads PlayerClip_<clip>.usdc; a missing clip no-ops cleanly.
    func playStance(_ clip: String, delay: TimeInterval = 0) {
        guard let base = Self.clip(clip)?.copy() as? CAAnimation else { return }
        base.repeatCount = 1
        base.fadeInDuration = 0.25    // ease in from the idle/run underneath
        base.fadeOutDuration = 0.2
        base.isRemovedOnCompletion = false
        base.fillMode = .forwards     // hold the stance's final frame
        if delay > 0 { base.beginTime = CACurrentMediaTime() + delay }
        skeleton.addAnimation(base, forKey: "stance")
    }

    /// Drop the held pre-snap stance (the snap breaks it; also on a full reset).
    func clearStance() {
        skeleton.removeAnimation(forKey: "stance", blendOutDuration: 0.1)
    }

    /// Resolve an action to a concrete clip name: pick a pool variant (avoiding an
    /// immediate repeat), or return the action itself if it has no variety pool.
    private func pickVariant(for action: String) -> String {
        guard let pool = Self.variantPools[action], !pool.isEmpty else { return action }
        if pool.count == 1 { return pool[0] }
        let fresh = pool.filter { $0 != lastVariant[action] }
        let pick = (fresh.isEmpty ? pool : fresh).randomElement() ?? pool[0]
        lastVariant[action] = pick
        return pick
    }

    // MARK: Helpers
    private static func firstNode(in root: SCNNode, where pred: (SCNNode) -> Bool) -> SCNNode? {
        if pred(root) { return root }
        for c in root.childNodes { if let r = firstNode(in: c, where: pred) { return r } }
        return nil
    }
    private static func forEachGeometry(in root: SCNNode, _ body: (SCNGeometry) -> Void) {
        if let g = root.geometry { body(g) }
        for c in root.childNodes { forEachGeometry(in: c, body) }
    }
}
