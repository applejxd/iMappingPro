#if canImport(ARKit)
import ARKit
import RealityKit

// MARK: - Tracking State

enum TrackingState {
    case notAvailable
    case limited(ARCamera.TrackingState.Reason)
    case normal

    var displayText: String {
        switch self {
        case .notAvailable:
            return "トラッキング不可"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "初期化中..."
            case .relocalizing:
                return "再ローカライズ中..."
            case .excessiveMotion:
                return "動きが速すぎます"
            case .insufficientFeatures:
                return "テクスチャが不足しています"
            @unknown default:
                return "制限中..."
            }
        case .normal:
            return "トラッキング正常"
        }
    }

    var isUsable: Bool {
        if case .normal = self { return true }
        return false
    }
}

// MARK: - ARSessionManagerDelegate

@MainActor
protocol ARSessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: ARSessionManager, didUpdate frame: ARFrame, relativePose: simd_float4x4)
    func sessionManager(_ manager: ARSessionManager, trackingStateChanged state: TrackingState)
    func sessionManager(_ manager: ARSessionManager, didFailWithError error: Error)
}

// MARK: - ARSessionManager

/// ARKit セッションの管理・フレームデータ取得を担当
final class ARSessionManager: NSObject, ARSessionDelegate {

    // MARK: - Properties

    weak var delegate: ARSessionManagerDelegate?

    private(set) var arSession: ARSession = ARSession()
    private var initialTransform: simd_float4x4?
    private var isCapturing: Bool = false

    /// LiDAR 非対応デバイスかどうか
    static var isLiDARSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - Session Control

    /// ARKit セッションを開始する
    func startSession() {
        guard Self.isLiDARSupported else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.sessionManager(self, didFailWithError: ARSessionError.lidarNotSupported)
            }
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.planeDetection = [.horizontal, .vertical]

        arSession.delegate = self
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    /// キャプチャを開始（初期姿勢をリセット）
    func startCapture() {
        initialTransform = nil
        isCapturing = true
    }

    /// キャプチャを停止（セッションは維持）
    func stopCapture() {
        isCapturing = false
    }

    /// セッションを一時停止
    func pauseSession() {
        arSession.pause()
    }

    /// セッションを完全リセット
    func resetSession() {
        stopCapture()
        initialTransform = nil
        startSession()
    }

    // MARK: - Pose Calculation

    /// 初期フレームを原点とした相対変換行列を計算する
    ///
    /// 相対座標系はスキャン開始時のポートレート表示基準（`CoordinateSystem` 参照）で、
    /// ARKit のランドスケープ基準カメラ座標系から Z 軸まわりに -90° 回転させて揃える。
    func relativeTransform(from cameraTransform: simd_float4x4) -> simd_float4x4 {
        if initialTransform == nil {
            initialTransform = cameraTransform
        }
        return CoordinateSystem.relativeTransform(initial: initialTransform!, current: cameraTransform)
    }

    // MARK: - Mesh Snapshot

    /// 現在のシーン再構成メッシュを、スキャン開始地点を原点とする相対座標系で取得する
    func snapshotMeshChunks() -> [MeshChunk] {
        guard #available(iOS 13.4, *), let frame = arSession.currentFrame else { return [] }
        let reference = CoordinateSystem.referenceTransform(
            initial: initialTransform ?? matrix_identity_float4x4
        )
        return frame.anchors.compactMap { anchor in
            guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }
            return MeshExporter.chunk(from: meshAnchor, referenceTransform: reference)
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isCapturing else { return }

        let relativePose = relativeTransform(from: frame.camera.transform)
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, didUpdate: frame, relativePose: relativePose)
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state: TrackingState
        switch camera.trackingState {
        case .normal:
            state = .normal
        case .notAvailable:
            state = .notAvailable
        case .limited(let reason):
            state = .limited(reason)
        @unknown default:
            state = .notAvailable
        }
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, trackingStateChanged: state)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, didFailWithError: error)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, trackingStateChanged: .notAvailable)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // セッション再開
        startSession()
    }
}

// MARK: - ARSessionError

enum ARSessionError: LocalizedError {
    case lidarNotSupported
    case sessionFailed(String)

    var errorDescription: String? {
        switch self {
        case .lidarNotSupported:
            return "このデバイスは LiDAR Scanner に対応していません。iPhone 12 Pro 以降が必要です。"
        case .sessionFailed(let message):
            return "ARKit セッションエラー: \(message)"
        }
    }
}

#endif // canImport(ARKit)
