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
    /// 録画開始地点（相対座標系の原点）のワールド変換が確定・破棄されたときに通知する
    func sessionManager(_ manager: ARSessionManager, originDidChange transform: simd_float4x4?)
    /// 原点確定直後の姿勢の飛びから自動復帰したことを通知する
    ///
    /// それまでに引き渡したフレームは別の座標系のものになるため、受け手は破棄する必要がある。
    func sessionManagerDidRestartOrigin(_ manager: ARSessionManager)
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
    /// 原点確定前に姿勢の連続性を確認するゲート
    private var startStabilityGate = StartStabilityGate()
    /// この枚数までのキーフレームしか無い間の不連続は、原点を取り直して自動復帰する
    ///
    /// 記録開始直後は捨てても損失が小さく、ARKit の原点調整が原因のことが多いため、
    /// エラーでキャプチャを止めるよりやり直した方が実用的。
    private static let earlyRecoveryFrameLimit = 30
    /// 1 回のキャプチャで自動復帰を許す回数
    private static let maxEarlyRecoveryCount = 3
    private var earlyRecoveryCount = 0
    /// `didCapture` 通知を受信順で直列化する（`processingQueue` からのみ触る）
    private var pendingCaptureDeliveryTask: Task<Void, Never>?

    /// 画像・深度のエンコードを行う直列キュー
    ///
    /// JPEG/PNG エンコードはフレームあたり数十 ms かかるため、
    /// メインスレッド（`ARSessionDelegate` のコールバック先）で実行すると
    /// AR プレビューの描画が詰まってカクつく。
    private let processingQueue = DispatchQueue(
        label: "com.imappingpro.arcore.frame-processing",
        qos: .userInitiated
    )
    /// エンコード処理中のフレーム数（メインスレッドからのみ更新）
    private var inFlightEncodeCount: Int = 0
    /// 同時にエンコードするフレーム数の上限
    ///
    /// ARKit のピクセルバッファはプール由来で、保持している間は再利用されない。
    /// 多重にエンコードするとカメラのフレーム供給が滞るため 1 に制限し、
    /// エンコードが間に合わない間はキーフレーム採用を見送る（自動的に間引く）。
    private static let maxInFlightEncodes = 1
    /// 深度が取得できなかったフレーム数（`processingQueue` からのみ触る）
    private var processingMissingDepthCount: Int = 0
    /// キャプチャ世代。開始・リセットのたびに進め、前世代の遅延到達を捨てる
    private var captureGeneration: Int = 0

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
        // 分類（`.meshWithClassification`）は保存データで使わないうえ、
        // チャンクごとに推論が走ってフレーム落ちの原因になるため要求しない。
        configuration.sceneReconstruction = .mesh
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        // 平面検出の結果も利用していないため無効のままにする（毎フレームの解析コストを避ける）

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
        notifyOriginChanged(nil)
        isWaitingForValidStart = true
        nextFrameIndex = 0
        missingDepthCount = 0
        keyframeSelector.reset()
        startStabilityGate.reset()
        beginNewCaptureGeneration()
        captureRequiresReset = false
        earlyRecoveryCount = 0
        isCapturing = true
    }

    /// キャプチャ世代を進め、エンコード中フレームの結果を破棄対象にする
    private func beginNewCaptureGeneration() {
        captureGeneration &+= 1
        processingQueue.async { [weak self] in
            self?.processingMissingDepthCount = 0
        }
    }

    /// 原点を取り直してキャプチャを続行する
    ///
    /// 既に引き渡したフレームは別の座標系になるため、世代を進めて無効化し、
    /// デリゲートへ破棄を依頼する。
    private func restartOrigin() {
        initialTransform = nil
        notifyOriginChanged(nil)
        isWaitingForValidStart = true
        nextFrameIndex = 0
        missingDepthCount = 0
        keyframeSelector.reset()
        startStabilityGate.reset()
        beginNewCaptureGeneration()
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManagerDidRestartOrigin(self)
        }
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

    /// エンコード中フレームの引き渡しが完了するまで待つ
    ///
    /// エンコードは非同期のため、停止直後には未引き渡しのキーフレームが残り得る。
    /// 保存前にこれを待つことで、最後のキーフレームの取りこぼしを防ぐ。
    func flushPendingCaptures() async {
        let pendingDelivery: Task<Void, Never>? = await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                continuation.resume(returning: self?.pendingCaptureDeliveryTask)
            }
        }
        await pendingDelivery?.value
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
        notifyOriginChanged(nil)
        isWaitingForValidStart = false
        nextFrameIndex = 0
        missingDepthCount = 0
        keyframeSelector.reset()
        startStabilityGate.reset()
        beginNewCaptureGeneration()
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
            notifyOriginChanged(CoordinateSystem.referenceTransform(initial: cameraTransform))
        }
        return CoordinateSystem.relativeTransform(initial: initialTransform!, current: cameraTransform)
    }

    /// 録画開始地点（相対座標系の原点）のワールド変換
    ///
    /// 表示専用の座標軸を配置するために使う。保存データには影響しない。
    var originWorldTransform: simd_float4x4? {
        initialTransform.map { CoordinateSystem.referenceTransform(initial: $0) }
    }

    private func notifyOriginChanged(_ transform: simd_float4x4?) {
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, originDidChange: transform)
        }
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

        // 深度パイプラインが立ち上がり、トラッキングが正常になるまで採用を保留する。
        // さらに、姿勢が一定時間連続していることを確認してから原点を確定する。
        // ARKit は `.normal` 直後にワールド原点を調整することがあり、その瞬間を
        // 原点にすると直後のフレームが不連続と判定されてしまうため。
        // 判定は毎フレーム走るため、バッファのコピーは行わず利用可否だけを確認する。
        if isWaitingForValidStart {
            guard tracking.isReliable,
                  let depthMap = sceneDepth?.depthMap,
                  DepthProcessor.hasUsableDepth(pixelBuffer: depthMap) else {
                startStabilityGate.reset()
                return
            }
            let cameraTransform = frame.camera.transform
            let worldTranslation = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            guard startStabilityGate.evaluate(
                translation: worldTranslation,
                quaternion: simd_quaternion(cameraTransform),
                timestamp: frame.timestamp
            ) else {
                if let rejected = startStabilityGate.lastRejectedDelta {
                    logger.debug("""
                        原点確定を待機中: 姿勢が飛びました \
                        (dt: \(rejected.time, privacy: .public)s, \
                        dpos: \(rejected.translation, privacy: .public)m, \
                        drot: \(rejected.rotation, privacy: .public)rad)
                        """)
                }
                return
            }
            startStabilityGate.reset()
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
            let delta = keyframeSelector.lastMotionDelta
            if nextFrameIndex <= Self.earlyRecoveryFrameLimit,
               earlyRecoveryCount < Self.maxEarlyRecoveryCount {
                // 記録開始直後の飛びは ARKit 側の原点調整であることが多い。
                // 破棄しても損失が小さいので、エラーにせず原点を取り直す。
                earlyRecoveryCount += 1
                logger.warning("""
                    記録開始直後に姿勢の不連続を検出したため原点を取り直します \
                    (attempt: \(self.earlyRecoveryCount, privacy: .public), \
                    frames: \(self.nextFrameIndex, privacy: .public), \
                    dt: \(delta?.time ?? 0, privacy: .public)s, \
                    dpos: \(delta?.translation ?? 0, privacy: .public)m, \
                    drot: \(delta?.rotation ?? 0, privacy: .public)rad)
                    """)
                restartOrigin()
                return
            }
            // ワールド原点が切り替わった可能性があるため、既存軌跡との混在を防ぐ。
            isCapturing = false
            captureRequiresReset = true
            logger.warning("""
                姿勢の不連続を検出したためキャプチャを停止しました \
                (frames: \(self.nextFrameIndex, privacy: .public), \
                dt: \(delta?.time ?? 0, privacy: .public)s, \
                dpos: \(delta?.translation ?? 0, privacy: .public)m, \
                drot: \(delta?.rotation ?? 0, privacy: .public)rad)
                """)
            let delegate = delegate
            Task { @MainActor in
                delegate?.sessionManager(self, didFailWithError: ARSessionError.discontinuityDuringCapture)
            }
            return
        case .capture:
            break
        }

        // 直前のフレームのエンコードが終わるまでは採用を見送る。
        // `updateLast` を更新しないため、次のフレームで再び採用判定される。
        guard inFlightEncodeCount < Self.maxInFlightEncodes else { return }

        keyframeSelector.updateLast(translation: translation, quaternion: quaternion, timestamp: timestamp)

        // ARFrame 自体はコールバックを抜けると再利用されるが、CVPixelBuffer を保持している間は
        // プールへ返却されない。ここでは参照の取得だけを行い、重いエンコードは
        // バックグラウンドキューへ逃がしてメインスレッドを解放する。
        let colorBuffer = frame.capturedImage
        let depthBuffer = sceneDepth?.depthMap
        let confidenceBuffer = sceneDepth?.confidenceMap
        let intrinsics = frame.camera.intrinsics
        let imageSize = CVImageBufferGetEncodedSize(colorBuffer)
        let index = nextFrameIndex
        let generation = captureGeneration
        nextFrameIndex += 1
        inFlightEncodeCount += 1

        let delegate = delegate
        processingQueue.async { [weak self] in
            guard let self else { return }
            defer {
                DispatchQueue.main.async {
                    self.inFlightEncodeCount -= 1
                }
            }

            let colorData = DepthProcessor.colorToJPEGData(pixelBuffer: colorBuffer) ?? Data()
            let depthData = depthBuffer.flatMap { DepthProcessor.depthToBinary(pixelBuffer: $0) }
            let confidence = confidenceBuffer.map { DepthProcessor.confidenceSummary(pixelBuffer: $0) }

            if depthData == nil {
                self.processingMissingDepthCount += 1
                self.logger.warning("深度マップを取得できませんでした (index: \(index, privacy: .public))")
            }
            let missingDepthCount = self.processingMissingDepthCount

            let depthSize: CGSize
            if depthData != nil, let depthBuffer {
                depthSize = CGSize(
                    width: CVPixelBufferGetWidth(depthBuffer),
                    height: CVPixelBufferGetHeight(depthBuffer)
                )
            } else {
                depthSize = .zero
            }

            let captured = CapturedFrame(
                index: index,
                timestamp: timestamp,
                translation: translation,
                quaternion: quaternion,
                intrinsics: intrinsics,
                imageWidth: Int(imageSize.width),
                imageHeight: Int(imageSize.height),
                depthWidth: Int(depthSize.width),
                depthHeight: Int(depthSize.height),
                colorData: colorData,
                depthData: depthData,
                confidenceData: confidence?.pngData,
                quality: FrameQuality(
                    tracking: tracking,
                    depthValidRatio: depthData.flatMap { DepthProcessor.depthValidRatio(binary: $0) },
                    confidenceMean: confidence?.mean
                ),
                missingDepthCount: missingDepthCount
            )

            let previousDeliveryTask = self.pendingCaptureDeliveryTask
            self.pendingCaptureDeliveryTask = Task { @MainActor in
                await previousDeliveryTask?.value
                // 開始・リセットをまたいで到達したフレームは座標系が異なるため捨てる
                guard self.captureGeneration == generation else { return }
                self.missingDepthCount = missingDepthCount
                delegate?.sessionManager(self, didCapture: captured)
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = Self.trackingState(from: camera.trackingState)
        let delegate = delegate
        Task { @MainActor in
            delegate?.sessionManager(self, trackingStateChanged: state)
        }
    }

    /// 現在のトラッキング状態
    ///
    /// `cameraDidChangeTrackingState` は変化時にしか呼ばれないため、
    /// 画面復帰などで通知を取りこぼした場合の同期用に参照する。
    var currentTrackingState: TrackingState {
        guard let camera = arSession.currentFrame?.camera else { return .notAvailable }
        return Self.trackingState(from: camera.trackingState)
    }

    private static func trackingState(from state: ARCamera.TrackingState) -> TrackingState {
        switch state {
        case .normal:
            return .normal
        case .notAvailable:
            return .notAvailable
        case .limited(let reason):
            return .limited(reason)
        @unknown default:
            return .notAvailable
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
