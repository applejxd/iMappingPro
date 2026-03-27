import SwiftUI
import ARKit
import RealityKit

/// ARView を SwiftUI に統合するラッパービュー
struct ARContainerView: UIViewRepresentable {

    let arSession: ARSession
    var showMesh: Bool = true

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = arSession
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        updateMeshVisibility(arView, show: showMesh)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        updateMeshVisibility(arView, show: showMesh)
    }

    private func updateMeshVisibility(_ arView: ARView, show: Bool) {
        if show {
            arView.debugOptions = [.showSceneUnderstanding]
        } else {
            arView.debugOptions = []
        }
    }
}

#Preview {
    ARContainerView(arSession: ARSession())
}
