import XCTest
@testable import iMappingProCore

final class ScanSessionTests: XCTestCase {

    // MARK: - Init

    func testInitWithDefaults() {
        let session = ScanSession(name: "テスト")

        XCTAssertEqual(session.name, "テスト")
        XCTAssertEqual(session.frameCount, 0)
        XCTAssertEqual(session.durationSeconds, 0)
        XCTAssertEqual(session.directoryName, session.id.uuidString)
    }

    func testInitWithCustomValues() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000000)
        let session = ScanSession(
            id: id,
            name: "カスタム",
            createdAt: date,
            frameCount: 100,
            durationSeconds: 60.5,
            directoryName: "custom-dir"
        )

        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.name, "カスタム")
        XCTAssertEqual(session.createdAt, date)
        XCTAssertEqual(session.frameCount, 100)
        XCTAssertEqual(session.durationSeconds, 60.5)
        XCTAssertEqual(session.directoryName, "custom-dir")
    }

    func testDirectoryNameDefaultsToUUID() {
        let session = ScanSession(name: "test")
        XCTAssertEqual(session.directoryName, session.id.uuidString)
    }

    func testDirectoryNameCustom() {
        let session = ScanSession(name: "test", directoryName: "my-dir")
        XCTAssertEqual(session.directoryName, "my-dir")
    }

    // MARK: - Computed Properties

    func testFormattedDurationSeconds() {
        let session = ScanSession(name: "test", durationSeconds: 45)
        XCTAssertEqual(session.formattedDuration, "45秒")
    }

    func testFormattedDurationZero() {
        let session = ScanSession(name: "test", durationSeconds: 0)
        XCTAssertEqual(session.formattedDuration, "0秒")
    }

    func testFormattedDurationMinutesAndSeconds() {
        let session = ScanSession(name: "test", durationSeconds: 125)
        XCTAssertEqual(session.formattedDuration, "2分5秒")
    }

    func testFormattedDurationExactMinute() {
        let session = ScanSession(name: "test", durationSeconds: 60)
        XCTAssertEqual(session.formattedDuration, "1分0秒")
    }

    func testFormattedDurationFractionalSeconds() {
        // durationSeconds は Double なので小数点以下は切り捨てられる
        let session = ScanSession(name: "test", durationSeconds: 59.9)
        XCTAssertEqual(session.formattedDuration, "59秒")
    }

    func testEstimatedFileSizeMB() {
        let session = ScanSession(name: "test", frameCount: 100)
        // 1フレーム = 725KB, 100フレーム = 72500KB ≈ 70.8MB
        let expected = Double(100) * 725 * 1024 / (1024 * 1024)
        XCTAssertEqual(session.estimatedFileSizeMB, expected, accuracy: 0.01)
    }

    func testEstimatedFileSizeZeroFrames() {
        let session = ScanSession(name: "test", frameCount: 0)
        XCTAssertEqual(session.estimatedFileSizeMB, 0)
    }

    func testFormattedDate() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let session = ScanSession(name: "test", createdAt: date)
        // formattedDate は ja_JP ロケールの short スタイル
        // 具体的なフォーマットはタイムゾーンに依存するため、空でないことのみ確認
        XCTAssertFalse(session.formattedDate.isEmpty)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = ScanSession(
            name: "テストスキャン",
            frameCount: 50,
            durationSeconds: 120.5
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScanSession.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.frameCount, decoded.frameCount)
        XCTAssertEqual(original.durationSeconds, decoded.durationSeconds)
        XCTAssertEqual(original.directoryName, decoded.directoryName)
        // Date は ISO8601 エンコードの精度で若干の差が出る可能性
        XCTAssertEqual(
            original.createdAt.timeIntervalSince1970,
            decoded.createdAt.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testNameMutation() {
        var session = ScanSession(name: "元の名前")
        session.name = "新しい名前"
        XCTAssertEqual(session.name, "新しい名前")
    }
}

// MARK: - SessionsContainer Tests

final class SessionsContainerTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let sessions = [
            ScanSession(name: "セッション1", frameCount: 10),
            ScanSession(name: "セッション2", frameCount: 20),
        ]
        let container = SessionsContainer(sessions: sessions)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(container)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionsContainer.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[0].name, "セッション1")
        XCTAssertEqual(decoded.sessions[1].name, "セッション2")
    }

    func testEmptySessions() throws {
        let container = SessionsContainer(sessions: [])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(container)

        let decoded = try JSONDecoder().decode(SessionsContainer.self, from: data)
        XCTAssertEqual(decoded.sessions.count, 0)
        XCTAssertEqual(decoded.version, 1)
    }
}
