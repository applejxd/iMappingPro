#if canImport(SwiftUI) && canImport(SceneKit)
import SwiftUI
import SceneKit
import SceneKit.ModelIO

/// 保存済みメッシュ (mesh.obj) の 3D プレビュー
struct MeshPreviewView: View {

    let meshURL: URL

    @State private var scene: SCNScene?
    @State private var isLoading: Bool = true

    var body: some View {
        ZStack {
            if let scene {
                SceneKitContainer(scene: scene)
            } else if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("メッシュを読み込めませんでした")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: meshURL) {
            await loadScene()
        }
    }

    private func loadScene() async {
        isLoading = true
        let url = meshURL
        let loaded = await Task.detached(priority: .userInitiated) { () -> SendableScene? in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            let scene = SCNScene(mdlAsset: asset)
            return SendableScene(scene: scene)
        }.value
        scene = loaded?.scene
        isLoading = false
    }
}

// MARK: - SendableScene

/// SCNScene をアクター境界を越えて受け渡すためのラッパ（読み込み直後で他から参照されないため安全）
private struct SendableScene: @unchecked Sendable {
    let scene: SCNScene
}

// MARK: - SceneKitContainer

private struct SceneKitContainer: UIViewRepresentable {

    let scene: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = .clear
        view.scene = scene
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== scene {
            uiView.scene = scene
        }
    }
}

#endif // canImport(SwiftUI) && canImport(SceneKit)
