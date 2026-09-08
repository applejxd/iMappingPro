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
    /// 深度が取得できなかったフレーム数
    @Published var missingDepthCount: Int = 0
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var savedSession: ScanSession?
    /// 録画開始地点（相対座標系の原点）のワールド変換
    ///
    /// AR プレビューに座標軸を表示するためだけに使い、保存データには含めない。
    @Published var originTransform: simd_float4x4?

    /// AR プレビューに表示する座標軸の変換
    ///
    /// 計測中（スキャン中・一時停止中）のみ表示し、待機中や保存中は表示しない。
    var displayedOriginTransform: simd_float4x4? {
        switch scanState {
        case .scanning, .paused:
            return originTransform
        case .idle, .saving:
            return nil
        }
    }

    // MARK: - Dependencies

    let sessionManager = ARSessionManager()
    private let storage = SessionStorage()

    // MARK: - Private

    private var capturedRecords: [CapturedFrame] = []
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

    /// プレビュー表示用に AR セッションを準備する
    ///
    /// スキャン中・一時停止中に呼ばれた場合はトラッキングをリセットしないよう何もしない
    /// （タブ切り替えなどで再度 `onAppear` した際に原点がずれるのを防ぐ）
    func prepareSession() {
        guard scanState == .idle else { return }
        sessionManager.startSession()
    }

    func startScanning() {
        guard scanState == .idle else { return }
        capturedRecords = []
        totalDistance = 0
        frameCount = 0
        missingDepthCount = 0
        elapsedSeconds = 0
        lastCapturedTranslation = .zero
        savedSession = nil
        currentSessionID = nil

        // 既にプレビューで実行中のセッションを再 run するとワールド原点がリセットされ、
        // 直後のフレームの姿勢が不連続になるため、ここではキャプチャ開始のみ行う
        sessionManager.startSession()
        sessionManager.startCapture()
        sessionStartTime = Date()
        scanState = .scanning

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
        // 初期姿勢を維持したまま再開する（原点が移動すると姿勢が不連続になる）
        guard sessionManager.resumeCapture() else {
            errorMessage = "座標系の整合性を確認できないため再開できません。ここまでの結果を保存するか、リセットして再スキャンしてください。"
            return
        }
        scanState = .scanning
        startTimer()
    }

    func resetScanning() {
        guard scanState != .saving else { return }
        // 先にタイマーを止めてから値をリセットする
        // （停止前に 0 を代入すると、キャンセル済みタスクの最終書き込みで値が戻る）
        stopTimer()
        sessionManager.resetSession()
        capturedRecords = []
        frameCount = 0
        missingDepthCount = 0
        elapsedSeconds = 0
        totalDistance = 0
        lastCapturedTranslation = .zero
        sessionStartTime = nil
        currentSessionID = nil
        savedSession = nil
        scanState = .idle
    }

    func saveSession(name: String) {
        guard scanState != .saving, !isSaving else { return }
        guard !capturedRecords.isEmpty else {
            errorMessage = "保存するフレームがありません。スキャンを開始してください。"
            return
        }
        // 保存中にフレームが増えると保存内容と表示がずれるため、キャプチャとタイマーを止める
        sessionManager.stopCapture()
        stopTimer()
        isSaving = true
        scanState = .saving

        let sessionID = UUID()
        currentSessionID = sessionID
        let duration = elapsedSeconds
        // MainActor への到着順が前後しても保存順が崩れないよう index で整列する
        let records = capturedRecords.sorted { $0.index < $1.index }
        let frames = Self.poseFrames(from: records)
        let sessionName = name.isEmpty ? "スキャン \(Date().formatted())" : name
        let storage = self.storage
        // メッシュは Metal バッファ参照のため、セッション停止前にこの時点でスナップショットする
        let meshChunks = sessionManager.snapshotMeshChunks()

        Task.detached(priority: .userInitiated) {
            do {
                _ = try storage.createSessionDirectory(id: sessionID)

                // フレームデータを並列書き込み
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for (idx, record) in records.enumerated() {
                        group.addTask {
                            try storage.saveColorImage(record.colorData, index: idx, sessionID: sessionID)
                            if let depthData = record.depthData {
                                try storage.saveDepthMap(depthData, index: idx, sessionID: sessionID)
                            }
                            if let confData = record.confidenceData {
                                try storage.saveConfidenceMap(confData, index: idx, sessionID: sessionID)
                            }
                        }
                    }
                    try await group.waitForAll()
                }

                try storage.savePoses(frames, sessionID: sessionID)

                // RGB + 深度から色付き点群を生成して保存（メッシュの色情報の代替）
                let points = PointCloudExporter.buildPointCloud(
                    frames: frames,
                    colorJPEGs: records.map { record -> Data? in
                        record.colorData.isEmpty ? nil : record.colorData
                    },
                    depthBinaries: records.map { $0.depthData }
                )
                if !points.isEmpty {
                    try storage.savePointCloud(PointCloudExporter.plyData(points: points), sessionID: sessionID)
                }

                // 統合メッシュを OBJ として保存
                var meshStatistics: MeshStatistics?
                if !meshChunks.isEmpty, let meshData = MeshExporter.objData(chunks: meshChunks) {
                    try storage.saveMesh(meshData, sessionID: sessionID)
                    meshStatistics = MeshExporter.statistics(of: meshChunks)
                }

                let session = ScanSession(
                    id: sessionID,
                    name: sessionName,
                    frameCount: frames.count,
                    durationSeconds: duration,
                    meshVertexCount: meshStatistics?.vertexCount,
                    meshFaceCount: meshStatistics?.faceCount
                )
                try storage.saveMetadata(session)

                var allSessions = try storage.loadAllSessions()
                allSessions.append(session)
                try storage.saveSessionList(allSessions)

                await MainActor.run { [session] in
                    self.savedSession = session
                    self.isSaving = false
                    self.scanState = .idle
                    self.capturedRecords = []
                    // 次のスキャンに備えて表示値もリセットする
                    self.frameCount = 0
                    self.missingDepthCount = 0
                    self.elapsedSeconds = 0
                    self.totalDistance = 0
                    self.lastCapturedTranslation = .zero
                    self.sessionStartTime = nil
                    self.currentSessionID = nil
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
        // 二重起動防止（複数タスクが elapsedSeconds を奪い合うのを防ぐ）
        stopTimer()
        let startTime = Date()
        let baseElapsed = elapsedSeconds
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                } catch {
                    // キャンセル時はここで抜ける（抜けずに書き込むとリセット値が上書きされる）
                    break
                }
                guard !Task.isCancelled, let self else { break }
                let elapsed = baseElapsed + Date().timeIntervalSince(startTime)
                self.elapsedSeconds = elapsed
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Pose Frames

    /// キャプチャ結果から保存用の `PoseFrame` 配列を作る
    ///
    /// フレーム番号は保存順で振り直し、末尾の数フレームには品質フラグを立てる
    /// （保存操作時の手ブレで視覚拘束が弱くなりやすい区間のため）。
    static func poseFrames(from records: [CapturedFrame]) -> [PoseFrame] {
        let trailingStart = max(records.count - FrameQuality.trailingFrameCount, 0)
        return records.enumerated().map { index, record in
            PoseFrame(
                index: index,
                timestamp: record.timestamp,
                translation: record.translation,
                quaternion: record.quaternion,
                focalLengthX: record.intrinsics[0][0],
                focalLengthY: record.intrinsics[1][1],
                principalPointX: record.intrinsics[2][0],
                principalPointY: record.intrinsics[2][1],
                imageWidth: record.imageWidth,
                imageHeight: record.imageHeight,
                depthWidth: record.depthWidth,
                depthHeight: record.depthHeight,
                quality: record.quality.markingTrailing(index >= trailingStart)
            )
        }
    }
}

// MARK: - ARSessionManagerDelegate

extension ScanViewModel: ARSessionManagerDelegate {

    func sessionManager(_ manager: ARSessionManager, didCapture frame: CapturedFrame) {
        // 停止・リセット・保存中に遅延到達したフレームは取り込まない
        guard scanState == .scanning else { return }

        capturedRecords.append(frame)
        frameCount = capturedRecords.count
        missingDepthCount = frame.missingDepthCount
        // 累積移動距離を計算
        totalDistance += simd_length(frame.translation - lastCapturedTranslation)
        lastCapturedTranslation = frame.translation
    }

    func sessionManager(_ manager: ARSessionManager, originDidChange transform: simd_float4x4?) {
        originTransform = transform
    }

    func sessionManager(_ manager: ARSessionManager, trackingStateChanged state: TrackingState) {
        trackingState = state
    }

    func sessionManager(_ manager: ARSessionManager, didFailWithError error: Error) {
        errorMessage = error.localizedDescription
        // セッション側でキャプチャが止められた場合は UI も一時停止状態に合わせる
        if scanState == .scanning {
            stopTimer()
            scanState = .paused
        }
    }
}

#endif // canImport(ARKit) && canImport(Combine)
