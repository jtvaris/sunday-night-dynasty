import SwiftUI
import SceneKit

// MARK: - SceneKitFieldView

/// A UIViewRepresentable that wraps an SCNView displaying a FootballFieldScene.
/// `allowsCameraControl` opts into SceneKit's free pan/zoom gestures — fine
/// for the replay viewer, but the live coached game must keep it OFF: the
/// first touch on the field would hand the shot to SceneKit's user camera
/// and every scripted focus/follow move afterwards would stop reaching the
/// screen (the Coach/Broadcast framing would appear frozen).
struct SceneKitFieldView: UIViewRepresentable {

    let scene: FootballFieldScene
    var allowsCameraControl: Bool = true
    /// R39: non-nil enables DEBUG-only render instrumentation — first-frame
    /// latency (measured from the PerfLog mark of the same name) and a
    /// 5-second rolling FPS report. No-op in Release.
    var perfTag: String? = nil

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        #if DEBUG
        if let perfTag { PerfLog.lap("\(perfTag)_to_makeview", sinceMark: perfTag) }
        #endif
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = allowsCameraControl
        scnView.backgroundColor = UIColor(Color.backgroundPrimary)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        // The render delegate drives the per-frame foot-lock IK (and, in DEBUG,
        // perf instrumentation). Always installed so foot-lock runs in Release.
        context.coordinator.scene = scene
        scnView.delegate = context.coordinator
        #if DEBUG
        if let perfTag {
            context.coordinator.tag = perfTag
            PerfLog.lap("\(perfTag)_makeview_done", sinceMark: perfTag)
        }
        #endif
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Scene updates are driven by FootballFieldScene directly;
        // no per-SwiftUI-update work needed here.
        uiView.allowsCameraControl = allowsCameraControl
    }

    // MARK: Coordinator (R39 DEBUG render instrumentation)

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        /// The live scene, so the render loop can drive per-frame foot-lock IK.
        weak var scene: FootballFieldScene?

        /// After the clip poses the skeleton (animations applied) but before
        /// constraints resolve, pin each running figure's planted foot to the
        /// turf. This is the hook where the animated foot height reads clean for
        /// plant detection.
        func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
            scene?.updateFootLocks(atTime: time)
        }

        #if DEBUG
        var tag: String = "scene"
        private var firstFrameReported = false
        private var windowStart: TimeInterval = 0
        private var frameCount = 0
        private var worstFrame: TimeInterval = 0
        private var lastFrameTime: TimeInterval = 0

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if !firstFrameReported {
                firstFrameReported = true
                DispatchQueue.main.async { [tag] in
                    PerfLog.measure("\(tag)_first_frame", sinceMark: tag)
                }
                windowStart = time
                lastFrameTime = time
                return
            }

            frameCount += 1
            worstFrame = max(worstFrame, time - lastFrameTime)
            lastFrameTime = time

            // One rolling report every 5 s: average FPS + worst frame gap.
            let elapsed = time - windowStart
            if elapsed >= 5.0 {
                let fps = Double(frameCount) / elapsed
                let worstMs = worstFrame * 1000
                print(String(format: "PERF|%@_fps|avg=%.1f worst_frame_ms=%.1f", tag, fps, worstMs))
                windowStart = time
                frameCount = 0
                worstFrame = 0
            }
        }
        #endif
    }
}
