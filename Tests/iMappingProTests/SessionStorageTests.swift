import XCTest
@testable import iMappingProCore

final class SessionStorageTests: XCTestCase {

    private var storage: SessionStorage!
    private var testBaseDir: URL!

    override func setUp() {
        super.setUp()
        // テスト用の一時ディレクトリを使用
        testBaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iMappingProTests-\(UUID().uuidString)", isDirectory: true)
        storage = SessionStorage(baseDirectory: testBaseDir)
    }

    override func tearDown() {
        // テスト後にクリーンアップ
        try? FileManager.default.removeItem(at: testBaseDir)
        super.tearDown()
    }

    // MARK: - Prepare Directories

    func testPrepareDirectories() throws {
        try storage.prepareDirectories()

        XCTAssertTrue(FileManager.default.fileExists(atPath: testBaseDir.path))
        let sessionsDir = testBaseDir.appendingPathComponent("sessions", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionsDir.path))
    }

    func testPrepareDirectoriesIdempotent() throws {
        try storage.prepareDirectories()
        try storage.prepareDirectories() // 2回目もエラーにならない
        XCTAssertTrue(FileManager.default.fileExists(atPath: testBaseDir.path))
    }

    // MARK: - Session List

    func testLoadAllSessionsEmpty() throws {
        try storage.prepareDirectories()
        let sessions = try storage.loadAllSessions()
        XCTAssertEqual(sessions.count, 0)
    }

    func testSaveAndLoadSessionList() throws {
        try storage.prepareDirectories()

        let sessions = [
            ScanSession(name: "セッション1", frameCount: 10, durationSeconds: 30),
            ScanSession(name: "セッション2", frameCount: 20, durationSeconds: 60),
        ]
        try storage.saveSessionList(sessions)

        let loaded = try storage.loadAllSessions()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "セッション1")
        XCTAssertEqual(loaded[0].frameCount, 10)
        XCTAssertEqual(loaded[1].name, "セッション2")
        XCTAssertEqual(loaded[1].frameCount, 20)
    }

    func testSaveSessionListOverwrites() throws {
        try storage.prepareDirectories()

        try storage.saveSessionList([ScanSession(name: "old")])
        try storage.saveSessionList([ScanSession(name: "new1"), ScanSession(name: "new2")])

        let loaded = try storage.loadAllSessions()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "new1")
    }

    // MARK: - Session Directory

    func testCreateSessionDirectory() throws {
        try storage.prepareDirectories()
        let id = UUID()

        let dir = try storage.createSessionDirectory(id: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))

        let framesDir = dir.appendingPathComponent("frames", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: framesDir.path))
    }

    func testSessionDirectoryURL() {
        let id = UUID()
        let url = storage.sessionDirectoryURL(id: id)
        XCTAssertTrue(url.path.contains(id.uuidString))
        XCTAssertTrue(url.path.contains("sessions"))
    }

    func testFramesDirectoryURL() {
        let id = UUID()
        let url = storage.framesDirectoryURL(sessionID: id)
        XCTAssertTrue(url.path.contains("frames"))
        XCTAssertTrue(url.path.contains(id.uuidString))
    }

    // MARK: - Metadata

    func testSaveMetadata() throws {
        try storage.prepareDirectories()
        let session = ScanSession(name: "テスト", frameCount: 5, durationSeconds: 10)
        _ = try storage.createSessionDirectory(id: session.id)

        try storage.saveMetadata(session)

        let metadataURL = storage.sessionDirectoryURL(id: session.id)
            .appendingPathComponent("metadata.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.path))

        // メタデータを読み戻して検証
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(ScanSession.self, from: data)
        XCTAssertEqual(loaded.name, "テスト")
        XCTAssertEqual(loaded.frameCount, 5)
    }

    // MARK: - Poses

    func testSaveAndLoadPoses() throws {
        try storage.prepareDirectories()
        let sessionID = UUID()
        _ = try storage.createSessionDirectory(id: sessionID)

        let frames = [
            PoseFrame(
                index: 0, timestamp: 0,
                translation: SIMD3<Float>(0, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                focalLengthX: 1440, focalLengthY: 1440,
                principalPointX: 960, principalPointY: 720,
                imageWidth: 1920, imageHeight: 1440,
                depthWidth: 256, depthHeight: 192
            ),
            PoseFrame(
                index: 1, timestamp: 0.5,
                translation: SIMD3<Float>(1, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                focalLengthX: 1440, focalLengthY: 1440,
                principalPointX: 960, principalPointY: 720,
                imageWidth: 1920, imageHeight: 1440,
                depthWidth: 256, depthHeight: 192
            ),
        ]

        try storage.savePoses(frames, sessionID: sessionID)
        let loaded = try storage.loadPoses(sessionID: sessionID)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].index, 0)
        XCTAssertEqual(loaded[0].translationX, 0)
        XCTAssertEqual(loaded[1].index, 1)
        XCTAssertEqual(loaded[1].translationX, 1.0)
        XCTAssertEqual(loaded[1].timestamp, 0.5)
    }

    func testLoadPosesMissing() throws {
        try storage.prepareDirectories()
        let sessionID = UUID()
        _ = try storage.createSessionDirectory(id: sessionID)

        // poses.json がない場合は空配列
        let loaded = try storage.loadPoses(sessionID: sessionID)
        XCTAssertEqual(loaded.count, 0)
    }

    // MARK: - Frame Data

    func testSaveColorImage() throws {
        try storage.prepareDirectories()
        let sessionID = UUID()
        _ = try storage.createSessionDirectory(id: sessionID)

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        try storage.saveColorImage(imageData, index: 0, sessionID: sessionID)

        let url = storage.colorImageURL(index: 0, sessionID: sessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = try Data(contentsOf: url)
        XCTAssertEqual(loaded, imageData)
    }

    func testSaveDepthMap() throws {
        try storage.prepareDirectories()
        let sessionID = UUID()
        _ = try storage.createSessionDirectory(id: sessionID)

        let depthData = Data(repeating: 0x42, count: 100)
        try storage.saveDepthMap(depthData, index: 5, sessionID: sessionID)

        let url = storage.framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent("000005_depth.bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSaveConfidenceMap() throws {
        try storage.prepareDirectories()
        let sessionID = UUID()
        _ = try storage.createSessionDirectory(id: sessionID)

        let confData = Data(repeating: 0x01, count: 50)
        try storage.saveConfidenceMap(confData, index: 3, sessionID: sessionID)

        let url = storage.framesDirectoryURL(sessionID: sessionID)
            .appendingPathComponent("000003_conf.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testColorImageURL() {
        let sessionID = UUID()
        let url = storage.colorImageURL(index: 42, sessionID: sessionID)
        XCTAssertTrue(url.lastPathComponent == "000042_color.jpg")
    }

    func testColorImageURLPadding() {
        let sessionID = UUID()
        let url = storage.colorImageURL(index: 0, sessionID: sessionID)
        XCTAssertEqual(url.lastPathComponent, "000000_color.jpg")

        let url999 = storage.colorImageURL(index: 999999, sessionID: sessionID)
        XCTAssertEqual(url999.lastPathComponent, "999999_color.jpg")
    }

    // MARK: - Delete

    func testDeleteSession() throws {
        try storage.prepareDirectories()

        let session = ScanSession(name: "削除テスト", frameCount: 1)
        _ = try storage.createSessionDirectory(id: session.id)
        try storage.saveMetadata(session)
        try storage.saveSessionList([session])

        // 削除前: ディレクトリとリスト項目が存在
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: storage.sessionDirectoryURL(id: session.id).path
        ))
        XCTAssertEqual(try storage.loadAllSessions().count, 1)

        try storage.deleteSession(id: session.id)

        // 削除後: ディレクトリとリスト項目が削除
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.sessionDirectoryURL(id: session.id).path
        ))
        XCTAssertEqual(try storage.loadAllSessions().count, 0)
    }

    func testDeleteNonexistentSession() throws {
        try storage.prepareDirectories()
        try storage.saveSessionList([])

        // 存在しないセッションの削除はエラーにならない
        try storage.deleteSession(id: UUID())
        XCTAssertEqual(try storage.loadAllSessions().count, 0)
    }

    // MARK: - Rename

    func testRenameSession() throws {
        try storage.prepareDirectories()

        let session = ScanSession(name: "元の名前", frameCount: 1)
        _ = try storage.createSessionDirectory(id: session.id)
        try storage.saveMetadata(session)
        try storage.saveSessionList([session])

        try storage.renameSession(id: session.id, newName: "新しい名前")

        let loaded = try storage.loadAllSessions()
        XCTAssertEqual(loaded[0].name, "新しい名前")

        // metadata.json も更新されている
        let metadataURL = storage.sessionDirectoryURL(id: session.id)
            .appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(ScanSession.self, from: data)
        XCTAssertEqual(metadata.name, "新しい名前")
    }

    func testRenameNonexistentSession() throws {
        try storage.prepareDirectories()
        try storage.saveSessionList([])

        XCTAssertThrowsError(try storage.renameSession(id: UUID(), newName: "new")) { error in
            guard case StorageError.sessionNotFound = error else {
                XCTFail("Expected sessionNotFound error, got \(error)")
                return
            }
        }
    }
}
