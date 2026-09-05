#if canImport(SwiftUI) && canImport(SceneKit)
import SwiftUI
import SceneKit
import SceneKit.ModelIO
import simd

// MARK: - ScenePreviewSource

/// 3D プレビューの表示対象
enum ScenePreviewSource: Equatable {
    /// 統合メッシュ (mesh.obj)
    case mesh(URL)
    /// 色付き点群 (points.ply)
    case pointCloud(URL)

    var url: URL {
        switch self {
        case .mesh(let url), .pointCloud(let url):
            return url
        }
    }

    var isPointCloud: Bool {
        if case .pointCloud = self { return true }
        return false
    }
}

/// 保存済みメッシュ / 点群の 3D プレビュー
///
/// 相対座標系は「スキャン開始時のポートレート表示」基準（`CoordinateSystem` 参照）のため、
/// +Z 側からシーンを見る既定カメラを置くと、スキャン時と同じ正立した向きで表示される。
struct MeshPreviewView: View {

    let source: ScenePreviewSource

    @State private var scene: SCNScene?
    @State private var isLoading: Bool = true

    init(source: ScenePreviewSource) {
        self.source = source
    }

    init(meshURL: URL) {
        self.init(source: .mesh(meshURL))
    }

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
                    Text(failureMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: source.url) {
            await loadScene()
        }
    }

    private var failureMessage: String {
        switch source {
        case .mesh: return "メッシュを読み込めませんでした"
        case .pointCloud: return "点群を読み込めませんでした"
        }
    }

    private func loadScene() async {
        isLoading = true
        let source = self.source
        let loaded = await Task.detached(priority: .userInitiated) { () -> SendableScene? in
            guard FileManager.default.fileExists(atPath: source.url.path) else { return nil }
            switch source {
            case .mesh(let url):
                return ScenePreviewBuilder.meshScene(url: url).map(SendableScene.init)
            case .pointCloud(let url):
                return ScenePreviewBuilder.pointCloudScene(url: url).map(SendableScene.init)
            }
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

// MARK: - ScenePreviewBuilder

/// ファイルから SCNScene を組み立てるヘルパ
private enum ScenePreviewBuilder {

    static func meshScene(url: URL) -> SCNScene? {
        let asset = MDLAsset(url: url)
        asset.loadTextures()
        let scene = SCNScene(mdlAsset: asset)
        let bounds = asset.boundingBox
        addDefaultCamera(to: scene, minimum: bounds.minBounds, maximum: bounds.maxBounds)
        return scene
    }

    static func pointCloudScene(url: URL) -> SCNScene? {
        guard let data = try? Data(contentsOf: url),
              let points = PointCloudExporter.decodePLY(data),
              !points.isEmpty else { return nil }

        let positions = points.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
        var colors = points.map {
            SIMD3<Float>(
                Float($0.color.x) / 255,
                Float($0.color.y) / 255,
                Float($0.color.z) / 255
            )
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let colorData = colors.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        var indices = [UInt32](0..<UInt32(points.count))
        let indexData = indices.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 6

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]

        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        var minimum = points[0].position
        var maximum = points[0].position
        for point in points {
            minimum = SIMD3<Float>(
                min(minimum.x, point.position.x),
                min(minimum.y, point.position.y),
                min(minimum.z, point.position.z)
            )
            maximum = SIMD3<Float>(
                max(maximum.x, point.position.x),
                max(maximum.y, point.position.y),
                max(maximum.z, point.position.z)
            )
        }
        addDefaultCamera(to: scene, minimum: minimum, maximum: maximum)
        return scene
    }

    /// シーン全体が収まる位置に正立した既定カメラを配置する
    private static func addDefaultCamera(to scene: SCNScene, minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let extent = maximum - minimum
        guard extent.x.isFinite, extent.y.isFinite, extent.z.isFinite else { return }

        let center = (minimum + maximum) / 2
        let radius = max(simd_length(extent) / 2, 0.001)
        let fieldOfView: Float = 60
        let distance = radius / tan(fieldOfView / 2 * .pi / 180) * 1.2

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(fieldOfView)
        camera.zNear = Double(max(distance * 0.001, 0.001))
        camera.zFar = Double(distance * 10 + radius * 10)

        let node = SCNNode()
        node.camera = camera
        // 相対座標系は +Y が上・-Z が撮影方向。既定カメラは -Z を向くため回転は不要
        node.position = SCNVector3(center.x, center.y, center.z + distance)
        scene.rootNode.addChildNode(node)
    }
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
