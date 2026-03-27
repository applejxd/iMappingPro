import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published

    @Published var sessions: [ScanSession] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var sharingURL: URL?

    // MARK: - Dependencies

    private let storage = SessionStorage()

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
