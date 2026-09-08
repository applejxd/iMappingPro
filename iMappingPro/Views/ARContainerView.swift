#if canImport(SwiftUI) && canImport(UIKit) && canImport(ARKit) && canImport(RealityKit)
import SwiftUI
import UIKit
import ARKit
import RealityKit
#if canImport(simd)
import simd
#endif

/// ARView を SwiftUI に統合するラッパービュー
struct ARContainerView: UIViewRepresentable {

    let arSession: ARSession
    var showMesh: Bool = true
    /// 録画開始地点（相対座標系の原点）のワールド変換
    ///
    /// 表示専用の座標軸を配置するためだけに使う。RealityKit のエンティティは
    /// `ARMeshAnchor` ではないため、保存されるメッシュ・点群には含まれない。
    var originTransform: simd_float4x4? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = arSession
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        updateMeshVisibility(arView, show: showMesh)
        updateOriginAxes(arView, coordinator: context.coordinator)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        updateMeshVisibility(arView, show: showMesh)
        updateOriginAxes(arView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.removeOriginAnchor(from: arView)
    }

    private func updateMeshVisibility(_ arView: ARView, show: Bool) {
        if show {
            arView.debugOptions = [.showSceneUnderstanding]
        } else {
            arView.debugOptions = []
        }
    }

    private func updateOriginAxes(_ arView: ARView, coordinator: Coordinator) {
        guard let transform = originTransform else {
            coordinator.removeOriginAnchor(from: arView)
            return
        }
        coordinator.placeOriginAnchor(in: arView, transform: transform)
    }

    // MARK: - Coordinator

    /// 座標軸エンティティのライフサイクルを保持する
    final class Coordinator {

        private var originAnchor: AnchorEntity?
        private var placedTransform: simd_float4x4?

        func placeOriginAnchor(in arView: ARView, transform: simd_float4x4) {
            if let anchor = originAnchor,
               let placedTransform,
               placedTransform == transform,
               anchor.scene != nil {
                return
            }
            removeOriginAnchor(from: arView)

            let anchor = AnchorEntity(world: transform)
            anchor.addChild(Coordinator.makeAxesEntity())
            arView.scene.addAnchor(anchor)
            originAnchor = anchor
            placedTransform = transform
        }

        func removeOriginAnchor(from arView: ARView) {
            if let anchor = originAnchor {
                arView.scene.removeAnchor(anchor)
            }
            originAnchor = nil
            placedTransform = nil
        }

        /// X: 赤 / Y: 緑 / Z: 青 の座標軸を作る
        private static func makeAxesEntity() -> Entity {
            let axisLength: Float = 0.2
            let axisThickness: Float = 0.006
            let root = Entity()

            let axes: [(size: SIMD3<Float>, position: SIMD3<Float>, color: UIColor)] = [
                (SIMD3(axisLength, axisThickness, axisThickness), SIMD3(axisLength / 2, 0, 0), .systemRed),
                (SIMD3(axisThickness, axisLength, axisThickness), SIMD3(0, axisLength / 2, 0), .systemGreen),
                (SIMD3(axisThickness, axisThickness, axisLength), SIMD3(0, 0, axisLength / 2), .systemBlue)
            ]
            for axis in axes {
                let entity = ModelEntity(
                    mesh: .generateBox(size: axis.size),
                    materials: [UnlitMaterial(color: axis.color)]
                )
                entity.position = axis.position
                root.addChild(entity)
            }

            // 原点を示す小球
            let origin = ModelEntity(
                mesh: .generateSphere(radius: axisThickness * 1.5),
                materials: [UnlitMaterial(color: .white)]
            )
            root.addChild(origin)
            return root
        }
    }
}

#Preview {
    ARContainerView(arSession: ARSession())
}

#endif // canImport(SwiftUI) && canImport(UIKit) && canImport(ARKit) && canImport(RealityKit)
