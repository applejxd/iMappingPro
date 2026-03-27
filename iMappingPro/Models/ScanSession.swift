import Foundation

/// スキャンセッションのメタデータ
struct ScanSession: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var frameCount: Int
    var durationSeconds: Double
    /// Documents/iMappingPro/sessions/ 配下のディレクトリ名（= UUID 文字列）
    var directoryName: String

    // MARK: - Computed Properties

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: createdAt)
    }

    var formattedDuration: String {
        let seconds = Int(durationSeconds)
        if seconds < 60 {
            return "\(seconds)秒"
        } else {
            let min = seconds / 60
            let sec = seconds % 60
            return "\(min)分\(sec)秒"
        }
    }

    var estimatedFileSizeMB: Double {
        // 1フレームあたり約725KB の概算
        let bytesPerFrame: Double = 725 * 1024
        return Double(frameCount) * bytesPerFrame / (1024 * 1024)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        frameCount: Int = 0,
        durationSeconds: Double = 0,
        directoryName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.frameCount = frameCount
        self.durationSeconds = durationSeconds
        self.directoryName = directoryName ?? id.uuidString
    }
}

// MARK: - Sessions Container

/// sessions.json のルートオブジェクト
struct SessionsContainer: Codable {
    var version: Int = 1
    var sessions: [ScanSession]
}
