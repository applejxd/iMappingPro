import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - SessionStorageProtocol

/// テスト時にモック差し替え可能にするためのプロトコル
protocol SessionStorageProtocol {
    func prepareDirectories() throws
    func loadAllSessions() throws -> [ScanSession]
    func saveSessionList(_ sessions: [ScanSession]) throws
    func sessionDirectoryURL(id: UUID) -> URL
    func framesDirectoryURL(sessionID: UUID) -> URL
    func createSessionDirectory(id: UUID) throws -> URL
    func saveMetadata(_ session: ScanSession) throws
    func savePoses(_ frames: [PoseFrame], sessionID: UUID) throws
    func loadPoses(sessionID: UUID) throws -> [PoseFrame]
    func saveColorImage(_ data: Data, index: Int, sessionID: UUID) throws
    func saveDepthMap(_ data: Data, index: Int, sessionID: UUID) throws
    func saveConfidenceMap(_ data: Data, index: Int, sessionID: UUID) throws
    func colorImageURL(index: Int, sessionID: UUID) -> URL
    func depthMapURL(index: Int, sessionID: UUID) -> URL
    func meshURL(sessionID: UUID) -> URL
    func saveMesh(_ data: Data, sessionID: UUID) throws
    func hasMesh(sessionID: UUID) -> Bool
    func loadMesh(sessionID: UUID) throws -> Data
    func createSessionArchive(id: UUID) throws -> URL
    func deleteSession(id: UUID) throws
    func renameSession(id: UUID, newName: String) throws
}

extension SessionStorage: SessionStorageProtocol {}

#if canImport(Combine)

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published

    @Published var sessions: [ScanSession] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var sharingURL: URL?
    @Published var isPreparingArchive: Bool = false

    // MARK: - Dependencies

    private let storage: SessionStorageProtocol

    // MARK: - Init

    init(storage: SessionStorageProtocol = SessionStorage()) {
        self.storage = storage
    }

    // MARK: - Load

    func loadSessions() {
        isLoading = true
        Task {
            do {
                sessions = try storage.loadAllSessions()
                    .sorted { $0.createdAt > $1.createdAt }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Delete

    func deleteSession(_ session: ScanSession) {
        Task {
            do {
                try storage.deleteSession(id: session.id)
                sessions.removeAll { $0.id == session.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteSessions(at indexSet: IndexSet) {
        let toDelete = indexSet.map { sessions[$0] }
        for session in toDelete {
            deleteSession(session)
        }
    }

    // MARK: - Rename

    func renameSession(_ session: ScanSession, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do {
                try storage.renameSession(id: session.id, newName: newName)
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index].name = newName
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Load Frames

    func loadFrames(for session: ScanSession) -> [PoseFrame] {
        (try? storage.loadPoses(sessionID: session.id)) ?? []
    }

    // MARK: - Session Directory

    func sessionDirectoryURL(for session: ScanSession) -> URL {
        storage.sessionDirectoryURL(id: session.id)
    }

    func colorImageURL(index: Int, sessionID: UUID) -> URL {
        storage.colorImageURL(index: index, sessionID: sessionID)
    }

    func depthMapURL(index: Int, sessionID: UUID) -> URL {
        storage.depthMapURL(index: index, sessionID: sessionID)
    }

    // MARK: - Mesh

    func meshURL(for session: ScanSession) -> URL {
        storage.meshURL(sessionID: session.id)
    }

    func hasMesh(_ session: ScanSession) -> Bool {
        storage.hasMesh(sessionID: session.id)
    }

    // MARK: - Share

    /// ダウンロード（共有）対象の種類
    enum ShareTarget {
        /// セッションディレクトリ全体（RGB・深度・姿勢・メッシュ）を ZIP 化
        case archive
        /// 統合メッシュ (mesh.obj) のみ
        case mesh
        /// 姿勢データ (poses.json) のみ
        case poses
    }

    func shareSession(_ session: ScanSession, target: ShareTarget = .archive) {
        switch target {
        case .poses:
            let posesURL = storage.sessionDirectoryURL(id: session.id).appendingPathComponent("poses.json")
            provideSharingURL(posesURL, missingMessage: "共有するファイルが見つかりません。先にスキャンを保存してください。")

        case .mesh:
            provideSharingURL(
                storage.meshURL(sessionID: session.id),
                missingMessage: "メッシュデータがありません。LiDAR 対応デバイスで再スキャンしてください。"
            )

        case .archive:
            isPreparingArchive = true
            let storage = self.storage
            let sessionID = session.id
            Task {
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try storage.createSessionArchive(id: sessionID)
                    }.value
                    sharingURL = url
                } catch {
                    errorMessage = error.localizedDescription
                }
                isPreparingArchive = false
            }
        }
    }

    private func provideSharingURL(_ url: URL, missingMessage: String) {
        if FileManager.default.fileExists(atPath: url.path) {
            sharingURL = url
        } else {
            errorMessage = missingMessage
        }
    }
}

#endif // canImport(Combine)
