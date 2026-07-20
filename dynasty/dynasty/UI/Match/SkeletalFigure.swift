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
    static let clipNames = ["run", "idle", "sprint", "tackle", "throw", "catch", "kick", "juke", "celebrate"]

    /// One-shot action clips retargeted from Mixamo carry a long lead-in/hold
    /// (throw 7.7s, tackle 5s, celebrate 4.5s) around a brief action beat; played
    /// at natural speed they drag. Compress each to a target on-screen duration so
    /// the beat lands in a football-appropriate window. Clips not listed play at
    /// natural speed (e.g. the Ochi kick).
    private static let actionTargetDuration: [String: TimeInterval] = [
        "throw": 2.2, "catch": 1.6, "tackle": 2.2, "juke": 0.75, "celebrate": 3.0,
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
        // A tackled figure holds the ground pose (key "fall"); moving clears it.
        skeleton.removeAnimation(forKey: "fall", blendOutDuration: 0.15)
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
        let k = max(0.35, min(3.0, groundSpeed / max(0.01, worldStride)))
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
        let active = (loco == .run || loco == .backpedal)
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
    }

    /// Fire a one-shot action clip (catch/tackle/throw…) over the locomotion.
    /// `delay` starts it later (sync a catch to the ball's arrival); `hold`
    /// keeps the final frame (a tackled man stays on the turf until he moves).
    func play(action name: String, delay: TimeInterval = 0, hold: Bool = false) {
        guard let base = Self.clip(name)?.copy() as? CAAnimation else { return }
        base.repeatCount = 1
        // Compress long retargeted clips to a football-appropriate beat length.
        if let target = Self.actionTargetDuration[name], base.duration > 0.01 {
            base.speed = Float(base.duration / target)
        }
        base.fadeInDuration = 0.2       // smoother blend from the run into the action
        base.fadeOutDuration = hold ? 0 : 0.3
        base.isRemovedOnCompletion = !hold
        if hold { base.fillMode = .forwards }
        if delay > 0 { base.beginTime = CACurrentMediaTime() + delay }
        skeleton.addAnimation(base, forKey: hold ? "fall" : "action")
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
