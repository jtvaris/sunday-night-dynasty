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

    /// The clip names shipped in Resources (PlayerClip_<name>.usdc). juke has no
    /// Studio Ochi equivalent (no-op); the rest map to the pack's football mocap.
    static let clipNames = ["run", "idle", "sprint", "tackle", "throw", "catch", "kick"]

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
    private var currentLoco: String = ""
    private var currentBackpedal = false
    /// Per-player signature so a squad never moves in lockstep: a phase offset
    /// into the loco cycle and a small cadence multiplier, both deterministic.
    private let phase01: CGFloat
    private let cadenceJitter: Float
    /// Which frame of the "Hold" clip to freeze on for the pre-snap idle
    /// (0 = upright, ~0.45 = deep crouch) — varies the stance by build + player.
    private let idleFraction: CGFloat

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
        self.cadenceJitter = 0.92 + Float(h2) / 65535.0 * 0.16   // 0.92–1.08
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
        applyUniform(jersey: jersey)
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
    /// Locomotion: run loop while moving, idle loop at rest. `speed` (yd/s)
    /// scales the run cadence so sprinters cycle faster than joggers.
    /// Locomotion: run/sprint while moving, idle at rest. `backpedal` plays the
    /// run clip in REVERSE so a QB dropback moves the legs backward instead of
    /// running forward while sliding back.
    func setMoving(_ moving: Bool, speed: Float, backpedal: Bool = false) {
        // A tackled figure holds the ground pose (key "fall"); moving clears it.
        skeleton.removeAnimation(forKey: "fall", blendOutDuration: 0.15)
        let want = moving ? (!backpedal && speed > 7.2 ? "sprint" : "run") : "idle"
        if want == currentLoco, backpedal == currentBackpedal {
            if moving { setRunSpeed(speed) }
            return
        }
        let prev = currentLoco
        currentLoco = want
        currentBackpedal = backpedal
        // cross into the new loco with a real blend; remove the previous so they
        // don't stack (its fade-out overlaps this one's fade-in = a transition).
        if !prev.isEmpty { skeleton.removeAnimation(forKey: "loco_\(prev)", blendOutDuration: 0.2) }
        guard let base = Self.clip(want)?.copy() as? CAAnimation else { return }
        base.repeatCount = .infinity
        base.fadeInDuration = 0.2
        base.fadeOutDuration = 0.2
        if moving {
            base.timeOffset = phase01 * base.duration   // desync the squad's gait
            base.speed = runSpeedFactor(speed) * (backpedal ? -1 : 1)
        } else {
            // Idle: the Studio Ochi "Hold" clip is a crouch cycle — looping it
            // makes the squad squat up and down. Freeze it on a per-player frame
            // (idleFraction) so builds hold varied stances instead of one pose.
            base.speed = 0
            base.timeOffset = idleFraction * base.duration
        }
        skeleton.addAnimation(base, forKey: "loco_\(want)")
    }

    private func setRunSpeed(_ speed: Float) {
        if let anim = skeleton.animationPlayer(forKey: "loco_\(currentLoco)") {
            anim.speed = CGFloat(runSpeedFactor(speed)) * (currentBackpedal ? -1 : 1)
        }
    }
    private func runSpeedFactor(_ speed: Float) -> Float {
        // Cadence tracks ground speed so the feet keep up (less foot-slide) —
        // a wider cap than before lets fast catch-up runs cycle their legs
        // instead of gliding. Per-player jitter breaks up lockstep.
        max(0.7, min(2.4, speed * 0.28)) * cadenceJitter
    }

    /// Fire a one-shot action clip (catch/tackle/throw…) over the locomotion.
    /// `delay` starts it later (sync a catch to the ball's arrival); `hold`
    /// keeps the final frame (a tackled man stays on the turf until he moves).
    func play(action name: String, delay: TimeInterval = 0, hold: Bool = false) {
        guard let base = Self.clip(name)?.copy() as? CAAnimation else { return }
        base.repeatCount = 1
        base.fadeInDuration = 0.1
        base.fadeOutDuration = hold ? 0 : 0.2
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
