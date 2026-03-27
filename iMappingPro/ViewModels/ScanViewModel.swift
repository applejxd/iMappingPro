#if canImport(ARKit)
import ARKit
#endif
#if canImport(Combine)
import Combine
#endif
#if canImport(simd)
import simd
#endif

// MARK: - ScanState

enum ScanState {
    case idle
    case scanning
    case paused
    case saving
}

#if canImport(ARKit) && canImport(Combine)

// MARK: - ScanViewModel

@MainActor
final class ScanViewModel: ObservableObject {

    // MARK: - Published

    @Published var scanState: ScanState = .idle
    @Published var trackingState: TrackingState = .notAvailable
    @Published var frameCount: Int = 0
    @Published var elapsedSeconds: Double = 0
    /// 開始地点からの累積移動距離（メートル）
    @Published var totalDistance: Float = 0
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var savedSession: ScanSession?

    // MARK: - Dependencies

    let sessionManager = ARSessionManager()
    private let depthProcessor = DepthProcessor()
    private let storage = SessionStorage()

    // MARK: - Private

    private var capturedFrames: [PoseFrame] = []
    private var pendingFrameData: [(colorData: Data, depthData: Data?, confData: Data?)] = []
    private var sessionStartTime: Date?
    private var currentSessionID: UUID?
    private var timerTask: Task<Void, Never>?
    private var lastCapturedTranslation: SIMD3<Float> = .zero

    // MARK: - Init

    init() {
        sessionManager.delegate = self
        try? storage.prepareDirectories()
    }

    // MARK: - Controls

    func startScanning() {
        guard scanState == .idle else { return }
        capturedFrames = []
        pendingFrameData = []
        totalDistance = 0
        frameCount = 0
        elapsedSeconds = 0
        lastCapturedTranslation = .zero

        sessionManager.startSession()
        sessionManager.startCapture()
        sessionStartTime = Date()
        scanState = .scanning
        depthProcessor.reset()

        startTimer()
    }

    func stopScanning() {
        guard scanState == .scanning else { return }
        sessionManager.stopCapture()
        stopTimer()
        scanState = .paused
    }

    func resumeScanning() {
        guard scanState == .paused else { return }
        sessionManager.startCapture()
        scanState = .scanning
        startTimer()
    }

    func resetScanning() {
        sessionManager.resetSession()
        capturedFrames = []
        pendingFrameData = []
        frameCount = 0
        elapsedSeconds = 0
        totalDistance = 0
        lastCapturedTranslation = .zero
        sessionStartTime = nil
        currentSessionID = nil
        depthProcessor.reset()
        stopTimer()
        scanState = .idle
    }

    func saveSession(name: String) {
        guard !capturedFrames.isEmpty else {
            errorMessage = "保存するフレームがありません。スキャンを開始してください。"
            return
        }
        isSaving = true
        scanState = .saving

        let sessionID = UUID()
        currentSessionID = sessionID
        let duration = elapsedSeconds
        let frames = capturedFrames
        let frameDataCopy = pendingFrameData
        let sessionName = name.isEmpty ? "スキャン \(Date().formatted())" : name
        let storage = self.storage

        Task.detached(priority: .userInitiated) {
            do {
                _ = try storage.createSessionDirectory(id: sessionID)

                // フレームデータを並列書き込み
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (i, data) in frameDataCopy.enumerated() {
                        let idx = i
                        group.addTask {
                            try storage.saveColorImage(data.colorData, index: idx, sessionID: sessionID)
                            if let depthData = data.depthData {
                                try storage.saveDepthMap(depthData, index: idx, sessionID: sessionID)
                            }
                            if let confData = data.confData {
                                try storage.saveConfidenceMap(confData, index: idx, sessionID: sessionID)
                            }
                        }
                    }
                    try await group.waitForAll()
                }

                try storage.savePoses(frames, sessionID: sessionID)

                let session = ScanSession(
                    id: sessionID,
                    name: sessionName,
                    frameCount: frames.count,
                    durationSeconds: duration
                )
                try storage.saveMetadata(session)

                var allSessions = try storage.loadAllSessions()
                allSessions.append(session)
                try storage.saveSessionList(allSessions)

                await MainActor.run { [session] in
                    self.savedSession = session
                    self.isSaving = false
                    self.scanState = .idle
                    self.capturedFrames = []
                    self.pendingFrameData = []
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSaving = false
                    self.scanState = .paused
                }
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        let startTime = Date()
        let baseElapsed = elapsedSeconds
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                guard let self else { break }
                let elapsed = baseElapsed + Date().timeIntervalSince(startTime)
                self.elapsedSeconds = elapsed
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - ARSessionManagerDelegate

extension ScanViewModel: ARSessionManagerDelegate {

    func sessionManager(
        _ manager: ARSessionManager,
        didUpdate frame: ARFrame,
        relativePose: simd_float4x4
    ) {
        let translation = SIMD3<Float>(
            relativePose.columns.3.x,
            relativePose.columns.3.y,
            relativePose.columns.3.z
        )
        let quaternion = simd_quaternion(relativePose)
        let timestamp = frame.timestamp
        let isFirst = capturedFrames.isEmpty

        guard depthProcessor.shouldCapture(
            translation: translation,
            quaternion: quaternion,
            timestamp: timestamp,
            isFirst: isFirst
        ) else { return }

        depthProcessor.updateLast(translation: translation, quaternion: quaternion, timestamp: timestamp)

        // 深度・カラーデータを収集（バックグラウンドは軽量なのでここで実行）
        let colorData = DepthProcessor.colorToJPEGData(pixelBuffer: frame.capturedImage)
        let depthData = frame.sceneDepth.flatMap { DepthProcessor.depthToBinary(pixelBuffer: $0.depthMap) }
        let confData  = frame.sceneDepth.flatMap { depth -> Data? in
            guard let confidenceMap = depth.confidenceMap else { return nil }
            return DepthProcessor.confidenceToData(pixelBuffer: confidenceMap)
        }

        let intrinsics = frame.camera.intrinsics
        let imageSize = CVImageBufferGetEncodedSize(frame.capturedImage)
        let depthSize: CGSize
        if let depthMap = frame.sceneDepth?.depthMap {
            depthSize = CGSize(
                width: CVPixelBufferGetWidth(depthMap),
                height: CVPixelBufferGetHeight(depthMap)
            )
        } else {
            depthSize = .zero
        }

        let frameIndex = capturedFrames.count
        let poseFrame = PoseFrame(
            index: frameIndex,
            timestamp: timestamp,
            translation: translation,
            quaternion: quaternion,
            focalLengthX: intrinsics[0][0],
            focalLengthY: intrinsics[1][1],
            principalPointX: intrinsics[2][0],
            principalPointY: intrinsics[2][1],
            imageWidth: Int(imageSize.width),
            imageHeight: Int(imageSize.height),
            depthWidth: Int(depthSize.width),
            depthHeight: Int(depthSize.height)
        )

        capturedFrames.append(poseFrame)
        pendingFrameData.append((colorData: colorData ?? Data(), depthData: depthData, confData: confData))
        frameCount = capturedFrames.count
        // 累積移動距離を計算
        totalDistance += simd_length(translation - lastCapturedTranslation)
        lastCapturedTranslation = translation
    }

    func sessionManager(_ manager: ARSessionManager, trackingStateChanged state: TrackingState) {
        trackingState = state
    }

    func sessionManager(_ manager: ARSessionManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
    }
}

#endif // canImport(ARKit) && canImport(Combine)
