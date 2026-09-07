#if canImport(ARKit)
import ARKit
import RealityKit
import os
#if canImport(simd)
import simd
#endif

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

// MARK: - CapturedFrame

/// ARKit のフレームからコピー済みのキャプチャ結果
///
/// `ARFrame` の `capturedImage` / `sceneDepth` はデリゲートコールバックの間だけ
/// 内容が保証されるプール由来のバッファのため、必ずこの値型へコピーしてから
/// 他のスレッド・アクターへ渡す。
struct CapturedFrame {
    let index: Int
    let timestamp: TimeInterval
    let translation: SIMD3<Float>
    let quaternion: simd_quatf
    let intrinsics: simd_float3x3
    let imageWidth: Int
    let imageHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let colorData: Data
    let depthData: Data?
    let confidenceData: Data?
    let quality: FrameQuality
    /// このフレームまでに深度が取得できなかった累計フレーム数
    let missingDepthCount: Int
}

// MARK: - ARSessionManagerDelegate

@MainActor
protocol ARSessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: ARSessionManager, didCapture frame: CapturedFrame)
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
    /// `arSession.run` 済みかどうか（二重 run によるワールド原点リセットを防ぐ）
    private(set) var isSessionRunning: Bool = false
    /// 割り込み開始時にセッションが実行中だったか
    private var wasSessionRunningBeforeInterruption: Bool = false
    /// 有効な最初のフレームを待っている状態か
    private var isWaitingForValidStart: Bool = false
    /// 座標系の整合性を失い、保存またはリセットが必要か
    private var captureRequiresReset: Bool = false
    /// 採用したフレームに与える連番
    private var nextFrameIndex: Int = 0
    /// 深度が取得できずスキップしたフレーム数
    private(set) var missingDepthCount: Int = 0

    private let keyframeSelector = DepthProcessor()
    /// `didCapture` 通知を受信順で直列化する
    private var pendingCaptureDeliveryTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.imappingpro.arcore", category: "ARSessionManager")

    /// LiDAR 非対応デバイスかどうか
    static var isLiDARSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - Session Control

    /// ARKit セッションを開始する
    ///
    /// 既に実行中の場合は何もしない。`resetTracking` が `true` のときだけ
    /// ワールド原点をリセットして再構成する。割り込み後のプレビュー復帰には
    /// `forceRestart` を指定して、原点をリセットせずに再実行する。
    /// 両方を指定した場合は `resetTracking` を優先する。
    func startSession(resetTracking: Bool = false, forceRestart: Bool = false) {
        guard Self.isLiDARSupported else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.sessionManager(self, didFailWithError: ARSessionError.lidarNotSupported)
            }
            return
        }

        guard resetTracking || forceRestart || !isSessionRunning else { return }

        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .meshWithClassification
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.planeDetection = [.horizontal, .vertical]

        arSession.delegate = self
        if resetTracking {
            arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            arSession.run(configuration)
        }
        isSessionRunning = true
    }

    /// キャプチャを開始（初期姿勢をリセット）
    ///
    /// 実際の原点はトラッキングが正常かつ深度が得られる最初のフレームで確定する。
    func startCapture() {
        initialTransform = nil
        isWaitingForValidStart = true
        nextFrameIndex = 0
        missingDepthCount = 0
        keyframeSelector.reset()
        captureRequiresReset = false
        isCapturing = true
    }

    /// キャプチャを再開（初期姿勢は維持し、座標系の原点を変えない）。
    ///
    /// 座標系の整合性を失った後は `false` を返し、再開しない。
    func resumeCapture() -> Bool {
        guard !captureRequiresReset else { return false }
        isCapturing = true
        return true
    }

    /// キャプチャを停止（セッションは維持）
    func stopCapture() {
        isCapturing = false
    }

    /// セッションを一時停止
    func pauseSession() {
        arSession.pause()
        isSessionRunning = false
    }

    /// セッションを完全リセット
    func resetSession() {
        stopCapture()
        initialTransform = nil
        isWaitingForValidStart = false
        nextFrameIndex = 0
        missingDepthCount = 0
        keyframeSelector.reset()
        startSession(resetTracking: true)
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

        let tracking = FrameTrackingQuality(frame.camera.trackingState)
        // 深度は平滑化済みを優先する（無効画素が少なく、低テクスチャ面でも穴が埋まりやすい）
        let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth
        var validatedStartDepthData: Data?

        // 深度パイプラインが立ち上がり、トラッキングが正常になるまで採用を保留する。
        // ここを通過した最初のフレームで初期姿勢（原点）を確定させる。
        if isWaitingForValidStart {
            guard tracking.isReliable,
                  let depthMap = sceneDepth?.depthMap,
                  let depthData = DepthProcessor.depthToBinary(pixelBuffer: depthMap) else { return }
            validatedStartDepthData = depthData
            isWaitingForValidStart = false
        }

        let relativePose = relativeTransform(from: frame.camera.transform)
        let translation = SIMD3<Float>(
            relativePose.columns.3.x,
            relativePose.columns.3.y,
            relativePose.columns.3.z
        )
        let quaternion = simd_quaternion(relativePose)
        let timestamp = frame.timestamp
        let isFirst = nextFrameIndex == 0

        switch keyframeSelector.evaluate(
            translation: translation,
            quaternion: quaternion,
            timestamp: timestamp,
            isFirst: isFirst,
            tracking: tracking
        ) {
        case .skip:
            return
        case .discontinuity:
            // ワールド原点が切り替わった可能性があるため、既存軌跡との混在を防ぐ。
            isCapturing = false
            captureRequiresReset = true
            logger.warning("姿勢の不連続を検出したためキャプチャを停止しました (timestamp: \(timestamp, privacy: .public))")
            let delegate = delegate
            Task { @MainActor in
                delegate?.sessionManager(self, didFailWithError: ARSessionError.discontinuityDuringCapture)
            }
            return
        case .capture:
            break
        }

        keyframeSelector.updateLast(translation: translation, quaternion: quaternion, timestamp: timestamp)

        // ARFrame のバッファはこのコールバック内でのみ有効なため、ここで Data 化する
        let colorData = DepthProcessor.colorToJPEGData(pixelBuffer: frame.capturedImage) ?? Data()
        let depthData = validatedStartDepthData
            ?? sceneDepth.flatMap { DepthProcessor.depthToBinary(pixelBuffer: $0.depthMap) }
        let confidenceData = sceneDepth.flatMap { depth -> Data? in
            guard let confidenceMap = depth.confidenceMap else { return nil }
            return DepthProcessor.confidenceToData(pixelBuffer: confidenceMap)
        }
        let confidenceMean = sceneDepth.flatMap { depth -> Float? in
            guard let confidenceMap = depth.confidenceMap else { return nil }
            return DepthProcessor.confidenceMean(pixelBuffer: confidenceMap)
        }

        if depthData == nil {
            missingDepthCount += 1
            logger.warning("深度マップを取得できませんでした (index: \(self.nextFrameIndex, privacy: .public))")
        }

        let depthSize: CGSize
        if depthData != nil, let depthMap = sceneDepth?.depthMap {
            depthSize = CGSize(
                width: CVPixelBufferGetWidth(depthMap),
                height: CVPixelBufferGetHeight(depthMap)
            )
        } else {
            depthSize = .zero
        }
        let imageSize = CVImageBufferGetEncodedSize(frame.capturedImage)

        let captured = CapturedFrame(
            index: nextFrameIndex,
            timestamp: timestamp,
            translation: translation,
            quaternion: quaternion,
            intrinsics: frame.camera.intrinsics,
            imageWidth: Int(imageSize.width),
            imageHeight: Int(imageSize.height),
            depthWidth: Int(depthSize.width),
            depthHeight: Int(depthSize.height),
            colorData: colorData,
            depthData: depthData,
            confidenceData: confidenceData,
            quality: FrameQuality(
                tracking: tracking,
                depthValidRatio: depthData.flatMap { DepthProcessor.depthValidRatio(binary: $0) },
                confidenceMean: confidenceMean
            ),
            missingDepthCount: missingDepthCount
        )
        nextFrameIndex += 1

        let delegate = delegate
        let previousDeliveryTask = pendingCaptureDeliveryTask
        pendingCaptureDeliveryTask = Task { @MainActor in
            await previousDeliveryTask?.value
            delegate?.sessionManager(self, didCapture: captured)
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
        isSessionRunning = false
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, didFailWithError: error)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        wasSessionRunningBeforeInterruption = isSessionRunning
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, trackingStateChanged: .notAvailable)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        let shouldRestartSession = wasSessionRunningBeforeInterruption
        wasSessionRunningBeforeInterruption = false

        guard isCapturing else {
            guard shouldRestartSession else { return }
            // プレビュー中は座標系を維持する必要がないため、セッションを再開する。
            startSession(forceRestart: true)
            return
        }

        if nextFrameIndex == 0 {
            // まだ1枚も採用していないので、次の有効フレームで原点を取り直せばよい
            isWaitingForValidStart = true
            return
        }

        // 既存フレームとは別のワールド座標系になっている可能性がある。
        // 黙って繋ぐと軌跡が壊れるため、キャプチャを停止してユーザに委ねる。
        isCapturing = false
        captureRequiresReset = true
        logger.warning("セッション中断のためキャプチャを停止しました (frames: \(self.nextFrameIndex, privacy: .public))")
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, didFailWithError: ARSessionError.interruptedDuringCapture)
        }
    }
}

// MARK: - FrameTrackingQuality + ARKit

extension FrameTrackingQuality {
    init(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            self = .normal
        case .notAvailable:
            self = .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing:          self = .limitedInitializing
            case .relocalizing:          self = .limitedRelocalizing
            case .excessiveMotion:       self = .limitedExcessiveMotion
            case .insufficientFeatures:  self = .limitedInsufficientFeatures
            @unknown default:            self = .limitedUnknown
            }
        @unknown default:
            self = .notAvailable
        }
    }
}

// MARK: - ARSessionError

enum ARSessionError: LocalizedError {
    case lidarNotSupported
    case sessionFailed(String)
    case interruptedDuringCapture
    case discontinuityDuringCapture

    var errorDescription: String? {
        switch self {
        case .lidarNotSupported:
            return "このデバイスは LiDAR Scanner に対応していません。iPhone 12 Pro 以降が必要です。"
        case .sessionFailed(let message):
            return "ARKit セッションエラー: \(message)"
        case .interruptedDuringCapture:
            return "セッションが中断されました。ワールド原点がずれる可能性があるため、キャプチャを停止しました。ここまでの結果を保存するか、リセットして再スキャンしてください。"
        case .discontinuityDuringCapture:
            return "姿勢の不連続を検出しました。ワールド原点がずれた可能性があるため、キャプチャを停止しました。ここまでの結果を保存するか、リセットして再スキャンしてください。"
        }
    }
}

#endif // canImport(ARKit)
