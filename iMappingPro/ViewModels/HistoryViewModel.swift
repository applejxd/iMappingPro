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

    // MARK: - Share

    func shareSession(_ session: ScanSession) {
        // poses.json を共有アイテムとして使用（ディレクトリは直接共有できないため）
        let posesURL = storage.sessionDirectoryURL(id: session.id).appendingPathComponent("poses.json")
        if FileManager.default.fileExists(atPath: posesURL.path) {
            sharingURL = posesURL
        } else {
            errorMessage = "共有するファイルが見つかりません。先にスキャンを保存してください。"
        }
    }
}

#endif // canImport(Combine)
