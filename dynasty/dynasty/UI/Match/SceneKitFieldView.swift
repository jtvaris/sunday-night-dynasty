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

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = allowsCameraControl
        scnView.backgroundColor = UIColor(Color.backgroundPrimary)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Scene updates are driven by FootballFieldScene directly;
        // no per-SwiftUI-update work needed here.
        uiView.allowsCameraControl = allowsCameraControl
    }
}
