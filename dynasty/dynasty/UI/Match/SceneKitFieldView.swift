import SwiftUI
import SceneKit

// MARK: - SceneKitFieldView

/// A UIViewRepresentable that wraps an SCNView displaying a FootballFieldScene.
/// The user can pan and zoom using standard SceneKit camera controls.
struct SceneKitFieldView: UIViewRepresentable {

    let scene: FootballFieldScene

    // MARK: UIViewRepresentable

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.allowsCameraControl = true
        scnView.backgroundColor = UIColor(Color.backgroundPrimary)
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics = false
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Scene updates are driven by FootballFieldScene directly;
        // no per-SwiftUI-update work needed here.
    }
}
