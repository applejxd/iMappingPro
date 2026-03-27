import Foundation
import simd

// MARK: - StorageError

enum StorageError: LocalizedError {
    case directoryCreationFailed(URL)
    case encodingFailed(String)
    case decodingFailed(String)
    case fileNotFound(URL)
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url):
            return "ディレクトリの作成に失敗しました: \(url.lastPathComponent)"
        case .encodingFailed(let detail):
            return "データのエンコードに失敗しました: \(detail)"
        case .decodingFailed(let detail):
            return "データのデコードに失敗しました: \(detail)"
        case .fileNotFound(let url):
            return "ファイルが見つかりません: \(url.lastPathComponent)"
        case .sessionNotFound(let id):
            return "セッションが見つかりません: \(id.uuidString)"
        }
    }
}

// MARK: - SessionStorage

/// スキャンセッションのファイル永続化を担当
final class SessionStorage {

    // MARK: - Paths

    private let fileManager = FileManager.default

    /// Documents/iMappingPro/
    private var baseDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("iMappingPro", isDirectory: true)
    }

    /// Documents/iMappingPro/sessions/
    private var sessionsDirectory: URL {
        baseDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    /// Documents/iMappingPro/sessions.json
    private var sessionsIndexURL: URL {
        baseDirectory.appendingPathComponent("sessions.json")
    }

    // MARK: - Setup

    /// 必要なディレクトリを初期化する
    func prepareDirectories() throws {
        try createDirectoryIfNeeded(at: baseDirectory)
        try createDirectoryIfNeeded(at: sessionsDirectory)
    }

    // MARK: - Session List

    func loadAllSessions() throws -> [ScanSession] {
        guard fileManager.fileExists(atPath: sessionsIndexURL.path) else {
            return []
        }
        let data = try Data(contentsOf: sessionsIndexURL)
        let container = try JSONDecoder().decode(SessionsContainer.self, from: data)
        return container.sessions
    }

    func saveSessionList(_ sessions: [ScanSession]) throws {
        let container = SessionsContainer(sessions: sessions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)
        try data.write(to: sessionsIndexURL, options: .atomic)
    }

    // MARK: - Session Directory

    func sessionDirectoryURL(id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func framesDirectoryURL(sessionID: UUID) -> URL {
        sessionDirectoryURL(id: sessionID).appendingPathComponent("frames", isDirectory: true)
    }

    func createSessionDirectory(id: UUID) throws -> URL {
        let dir = sessionDirectoryURL(id: id)
        try createDirectoryIfNeeded(at: dir)
        try createDirectoryIfNeeded(at: framesDirectoryURL(sessionID: id))
        return dir
    }

    // MARK: - Metadata

    func saveMetadata(_ session: ScanSession) throws {
        let url = sessionDirectoryURL(id: session.id).appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Poses

    func savePoses(_ frames: [PoseFrame], sessionID: UUID) throws {
        let container = PosesContainer(
            sessionId: sessionID.uuidString,
            frameCount: frames.count,
            frames: frames.map { PoseFrameJSON(from: $0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)
        let url = sessionDirectoryURL(id: sessionID).appendingPathComponent("poses.json")
        try data.write(to: url, options: .atomic)
    }

    func loadPoses(sessionID: UUID) throws -> [PoseFrame] {
        let url = sessionDirectoryURL(id: sessionID).appendingPathComponent("poses.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let container = try JSONDecoder().decode(PosesContainer.self, from: data)
        return container.frames.map { json in
            PoseFrame(
                index: json.index,
                timestamp: json.timestamp,
                translation: SIMD3<Float>(json.translation[0], json.translation[1], json.translation[2]),
                quaternion: simd_quatf(ix: json.quaternion[0], iy: json.quaternion[1], iz: json.quaternion[2], r: json.quaternion[3]),
                focalLengthX: json.intrinsics.fx,
                focalLengthY: json.intrinsics.fy,
                principalPointX: json.intrinsics.cx,
                principalPointY: json.intrinsics.cy,
                imageWidth: json.imageSize.width,
                imageHeight: json.imageSize.height,
                depthWidth: json.depthSize.width,
                depthHeight: json.depthSize.height
            )
        }
    }

    // MARK: - Frame Data

    func saveColorImage(_ data: Data, index: Int, sessionID: UUID) throws {
        let url = framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent(String(format: "%06d_color.jpg", index))
        try data.write(to: url, options: .atomic)
    }

    func saveDepthMap(_ data: Data, index: Int, sessionID: UUID) throws {
        let url = framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent(String(format: "%06d_depth.bin", index))
        try data.write(to: url, options: .atomic)
    }

    func saveConfidenceMap(_ data: Data, index: Int, sessionID: UUID) throws {
        let url = framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent(String(format: "%06d_conf.png", index))
        try data.write(to: url, options: .atomic)
    }

    func colorImageURL(index: Int, sessionID: UUID) -> URL {
        framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent(String(format: "%06d_color.jpg", index))
    }

    // MARK: - Delete

    func deleteSession(id: UUID) throws {
        let dir = sessionDirectoryURL(id: id)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        // sessions.json からも削除
        var sessions = try loadAllSessions()
        sessions.removeAll { $0.id == id }
        try saveSessionList(sessions)
    }

    // MARK: - Rename

    func renameSession(id: UUID, newName: String) throws {
        var sessions = try loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            throw StorageError.sessionNotFound(id)
        }
        sessions[index].name = newName
        try saveSessionList(sessions)

        // metadata.json も更新
        var session = sessions[index]
        session.name = newName
        try saveMetadata(session)
    }

    // MARK: - Private

    private func createDirectoryIfNeeded(at url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw StorageError.directoryCreationFailed(url)
        }
    }
}
