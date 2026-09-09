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
    /// 開始準備中（トラッキング安定待ち＋カウントダウン）
    case preparing
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
    /// 開始前カウントダウンの残り秒数（準備中のみ非 nil）
    @Published var countdown: Int?
    /// 一時的な通知（原点の取り直しなど）
    @Published var notice: String?

    /// AR プレビューに表示する座標軸の変換
    ///
    /// 計測中（スキャン中・一時停止中）のみ表示し、待機中や保存中は表示しない。
    var displayedOriginTransform: simd_float4x4? {
        switch scanState {
        case .scanning, .paused:
            return originTransform
        case .idle, .preparing, .saving:
            return nil
        }
    }

    /// LiDAR メッシュのプレビューを表示してよい状態か
    ///
    /// シーン理解の可視化は GPU 負荷が高く、トラッキング初期化中に有効にすると
    /// 収束が遅れるため、計測中（スキャン中・一時停止中）だけ表示する。
    var isMeshPreviewAvailable: Bool {
        switch scanState {
        case .scanning, .paused:
            return true
        case .idle, .preparing, .saving:
            return false
        }
    }

    /// トラッキング初期化ガイド（標準の coaching overlay）を表示するか
    var isCoachingActive: Bool {
        scanState == .preparing && !trackingState.isUsable
    }

    // MARK: - Dependencies

    let sessionManager = ARSessionManager()
    private let storage = SessionStorage()

    // MARK: - Private

    private var capturedRecords: [CapturedFrame] = []
    private var sessionStartTime: Date?
    private var currentSessionID: UUID?
    private var timerTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastCapturedTranslation: SIMD3<Float> = .zero
    /// 表示用に丸める前の経過時間（保存時の duration に使う）
    private var preciseElapsedSeconds: Double = 0
    /// 現在のスキャンのフレームを受け入れてよいか
    ///
    /// エンコードは非同期のため、一時停止・エラー停止の直後にもフレームが到着し得る。
    /// `scanState` で弾くと最後のキーフレームを取りこぼすため、
    /// リセットと保存確定のタイミングだけ受け入れを止める。
    private var isAcceptingCaptures: Bool = false

    /// 保存ダイアログを開いた時点で計測中だったか（キャンセル時に再開するため）
    private var wasScanningBeforeSavePrompt: Bool = false

    /// 開始前カウントダウンの秒数
    ///
    /// ARKit がワールド原点を確定させるまでの時間を稼ぐ目的も兼ねる。
    static let countdownDuration: Int = 3

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

    /// スキャン開始を要求する
    ///
    /// トラッキングが安定するまで待ってからカウントダウンし、その後にキャプチャを開始する。
    /// ARKit はセッション開始直後にワールド原点を調整することがあり、
    /// すぐに記録を始めると姿勢の不連続として検出されてしまうため。
    func startScanning() {
        guard scanState == .idle else { return }
        capturedRecords = []
        totalDistance = 0
        frameCount = 0
        missingDepthCount = 0
        elapsedSeconds = 0
        preciseElapsedSeconds = 0
        lastCapturedTranslation = .zero
        savedSession = nil
        currentSessionID = nil

        // 既にプレビューで実行中のセッションを再 run するとワールド原点がリセットされ、
        // 直後のフレームの姿勢が不連続になるため、ここでは準備のみ行う
        sessionManager.startSession()
        // デリゲート通知を取りこぼしている場合に備えて現在値を取り込む
        trackingState = sessionManager.currentTrackingState
        scanState = .preparing
        startCountdown()
    }

    /// 準備中のカウントダウンを取り消して待機状態へ戻す
    func cancelPreparing() {
        guard scanState == .preparing else { return }
        stopCountdown()
        scanState = .idle
    }

    private func startCountdown() {
        stopCountdown()
        countdownTask = Task { [weak self] in
            guard let self else { return }
            var remaining = Self.countdownDuration
            while remaining > 0 {
                guard !Task.isCancelled, self.scanState == .preparing else { return }
                guard self.trackingState.isUsable else {
                    // トラッキングが安定するまでカウントを進めない（coaching overlay が案内する）
                    self.countdown = nil
                    remaining = Self.countdownDuration
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                self.countdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            guard !Task.isCancelled, self.scanState == .preparing else { return }
            self.countdown = nil
            self.beginCapture()
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    private func beginCapture() {
        sessionManager.startCapture()
        isAcceptingCaptures = true
        sessionStartTime = Date()
        scanState = .scanning
        startTimer()
    }

    /// 一時的な通知を表示する（数秒後に自動で消える）
    private func showNotice(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
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

    /// 保存ダイアログを開く直前に呼ぶ
    ///
    /// 名前を入力している間もキャプチャを続けると、その間の姿勢変化や ARKit の
    /// トラッキング再初期化が「姿勢の不連続」として検出され、保存前にエラーで
    /// 停止してしまう。ダイアログ表示中はキャプチャを止めておく。
    func beginSavePrompt() {
        guard scanState == .scanning else { return }
        sessionManager.stopCapture()
        stopTimer()
        wasScanningBeforeSavePrompt = true
    }

    /// 保存ダイアログがキャンセルされたときに計測を元へ戻す
    func cancelSavePrompt() {
        guard wasScanningBeforeSavePrompt else { return }
        wasScanningBeforeSavePrompt = false
        guard scanState == .scanning else { return }
        guard sessionManager.resumeCapture() else {
            // ダイアログ表示中に座標系の整合性が失われた場合は一時停止として扱う
            scanState = .paused
            errorMessage = "座標系の整合性を確認できないため再開できません。ここまでの結果を保存するか、リセットして再スキャンしてください。"
            return
        }
        startTimer()
    }

    func resetScanning() {
        guard scanState != .saving else { return }
        wasScanningBeforeSavePrompt = false
        // 先にタイマーを止めてから値をリセットする
        // （停止前に 0 を代入すると、キャンセル済みタスクの最終書き込みで値が戻る）
        stopTimer()
        stopCountdown()
        sessionManager.resetSession()
        isAcceptingCaptures = false
        capturedRecords = []
        frameCount = 0
        missingDepthCount = 0
        elapsedSeconds = 0
        preciseElapsedSeconds = 0
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
        wasScanningBeforeSavePrompt = false
        // 保存中にフレームが増えると保存内容と表示がずれるため、キャプチャとタイマーを止める
        sessionManager.stopCapture()
        stopTimer()
        isSaving = true
        scanState = .saving

        Task { [weak self] in
            guard let self else { return }
            // エンコード中のキーフレームを取りこぼさないよう、引き渡し完了を待ってから確定する
            await self.sessionManager.flushPendingCaptures()
            self.isAcceptingCaptures = false
            self.performSave(name: name)
        }
    }

    private func performSave(name: String) {
        // 保存待ちの間に原点の取り直しでフレームが破棄されることがある
        guard !capturedRecords.isEmpty else {
            errorMessage = "保存できるフレームがありません。計測をやり直してください。"
            isSaving = false
            scanState = .paused
            return
        }

        let sessionID = UUID()
        currentSessionID = sessionID
        let duration = preciseElapsedSeconds
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
                    self.preciseElapsedSeconds = 0
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
        let baseElapsed = preciseElapsedSeconds
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
                self.preciseElapsedSeconds = elapsed
                // 表示は秒単位のため、秒が変わったときだけ発行して
                // ビュー全体（AR プレビューを含む）の再評価を 1/10 に減らす
                if Int(elapsed) != Int(self.elapsedSeconds) {
                    self.elapsedSeconds = elapsed
                }
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
        // リセット後・保存確定後に遅延到達したフレームは取り込まない
        guard isAcceptingCaptures else { return }

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

    func sessionManagerDidRestartOrigin(_ manager: ARSessionManager) {
        // 取り直し前のフレームは別座標系になるため、状態に関わらず必ず破棄する
        // （通知はメインアクターへの非同期到達なので、その間に停止・保存へ遷移し得る）
        capturedRecords = []
        frameCount = 0
        missingDepthCount = 0
        totalDistance = 0
        lastCapturedTranslation = .zero
        elapsedSeconds = 0
        preciseElapsedSeconds = 0

        guard scanState == .scanning else { return }
        sessionStartTime = Date()
        startTimer()
        showNotice("トラッキングが安定しなかったため、計測をやり直しました")
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
        } else if scanState == .preparing {
            // 準備中に失敗したらカウントダウンを止めて待機状態に戻す
            stopCountdown()
            scanState = .idle
        }
    }
}

#endif // canImport(ARKit) && canImport(Combine)
