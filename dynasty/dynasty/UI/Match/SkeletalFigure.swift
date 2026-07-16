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

    /// The clip names shipped in Resources (PlayerClip_<name>.usdc).
    static let clipNames = ["run", "idle", "sprint", "juke", "tackle"]

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
    /// Per-player signature so a squad never moves in lockstep: a phase offset
    /// into the loco cycle and a small cadence multiplier, both deterministic.
    private let phase01: CGFloat
    private let cadenceJitter: Float

    /// Builds one skinned player. `variantSeed` (e.g. jersey number) gives each
    /// player a stable, distinct gait phase + cadence. Returns nil if the rig
    /// asset is missing, so callers can fall back to the kit/procedural figure.
    init?(jersey: UIColor, pants: UIColor, helmet: UIColor, skin: UIColor, mask: UIColor,
          variantSeed: Int = 0) {
        // Deterministic 0..1 hashes from the seed (no RNG — stable per player).
        let h1 = (variantSeed &* 2654435761) & 0xffff
        let h2 = (variantSeed &* 40503 &+ 12345) & 0xffff
        self.phase01 = CGFloat(h1) / 65535.0
        self.cadenceJitter = 0.92 + Float(h2) / 65535.0 * 0.16   // 0.92–1.08
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
        wrapper.scale = SCNVector3(Self.scale, Self.scale, Self.scale)
        wrapper.position = SCNVector3(0, Self.yOffset, 0)
        wrapper.addChildNode(face)

        self.content = wrapper
        self.skeleton = skel
        tint(jersey: jersey, pants: pants, helmet: helmet, skin: skin, mask: mask)
        setMoving(false, speed: 0)   // idle by default
    }

    /// Re-tint by material slot name. The clone shares no geometry (each figure
    /// loads its own scene), so we can tint materials in place.
    func tint(jersey: UIColor, pants: UIColor, helmet: UIColor, skin: UIColor, mask: UIColor) {
        let colors: [String: UIColor] = [
            "JERSEY": jersey, "PANTS": pants, "HELMET": helmet, "SKIN": skin, "MASK": mask,
        ]
        Self.forEachGeometry(in: content) { geometry in
            for material in geometry.materials {
                if let name = material.name, let color = colors[name] {
                    material.diffuse.contents = color
                }
            }
        }
    }

    // MARK: Driving
    /// Locomotion: run loop while moving, idle loop at rest. `speed` (yd/s)
    /// scales the run cadence so sprinters cycle faster than joggers.
    func setMoving(_ moving: Bool, speed: Float) {
        // Three locomotion tiers: idle at rest, run at pace, sprint when flying.
        let want = moving ? (speed > 7.2 ? "sprint" : "run") : "idle"
        if want == currentLoco {
            if moving { setRunSpeed(speed) }
            return
        }
        let prev = currentLoco
        currentLoco = want
        // cross into the new loco with a real blend; remove the previous so they
        // don't stack (its fade-out overlaps this one's fade-in = a transition).
        if !prev.isEmpty { skeleton.removeAnimation(forKey: "loco_\(prev)", blendOutDuration: 0.22) }
        guard let base = Self.clip(want)?.copy() as? CAAnimation else { return }
        base.repeatCount = .infinity
        base.fadeInDuration = 0.22
        base.fadeOutDuration = 0.22
        if moving {
            base.timeOffset = phase01 * base.duration   // desync the squad's gait
            base.speed = runSpeedFactor(speed)
        } else {
            // Idle: the Studio Ochi "Hold" clip is a crouch-DOWN cycle — looping
            // it makes the whole squad squat up and down while waiting. Freeze it
            // on the upright first frame so they just stand at the ready.
            base.speed = 0
            base.timeOffset = 0
        }
        skeleton.addAnimation(base, forKey: "loco_\(want)")
    }

    private func setRunSpeed(_ speed: Float) {
        if let anim = skeleton.animationPlayer(forKey: "loco_\(currentLoco)") {
            anim.speed = CGFloat(runSpeedFactor(speed))
        }
    }
    private func runSpeedFactor(_ speed: Float) -> Float {
        // Cadence tracks ground speed (a ~4-yd stride at 0.96s/cycle) so the
        // feet plant closer to in-place; per-player jitter breaks up lockstep.
        max(0.65, min(1.9, speed * 0.24)) * cadenceJitter
    }

    /// Fire a one-shot action clip (juke/tackle/...) layered over locomotion.
    func play(action name: String) {
        guard let base = Self.clip(name)?.copy() as? CAAnimation else { return }
        base.repeatCount = 1
        base.fadeInDuration = 0.1
        base.fadeOutDuration = 0.2
        base.isRemovedOnCompletion = true
        skeleton.addAnimation(base, forKey: "action")
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
