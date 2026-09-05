import XCTest
@testable import iMappingProCore

final class SessionStorageMeshTests: XCTestCase {

    private var storage: SessionStorage!
    private var testBaseDir: URL!

    override func setUp() {
        super.setUp()
        testBaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iMappingProMeshTests-\(UUID().uuidString)", isDirectory: true)
        storage = SessionStorage(baseDirectory: testBaseDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testBaseDir)
        super.tearDown()
    }

    // MARK: - Mesh

    func testMeshURLLocation() {
        let id = UUID()
        XCTAssertEqual(storage.meshURL(sessionID: id).lastPathComponent, "mesh.obj")
        XCTAssertEqual(
            storage.meshURL(sessionID: id).deletingLastPathComponent(),
            storage.sessionDirectoryURL(id: id)
        )
    }

    func testSaveAndLoadMesh() throws {
        try storage.prepareDirectories()
        let id = UUID()
        _ = try storage.createSessionDirectory(id: id)

        XCTAssertFalse(storage.hasMesh(sessionID: id))

        let chunk = MeshChunk(
            vertices: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)],
            faces: [SIMD3<UInt32>(0, 1, 2)]
        )
        let data = try XCTUnwrap(MeshExporter.objData(chunks: [chunk]))
        try storage.saveMesh(data, sessionID: id)

        XCTAssertTrue(storage.hasMesh(sessionID: id))
        XCTAssertEqual(try storage.loadMesh(sessionID: id), data)
    }

    func testLoadMeshThrowsWhenMissing() throws {
        try storage.prepareDirectories()
        let id = UUID()
        _ = try storage.createSessionDirectory(id: id)
        XCTAssertThrowsError(try storage.loadMesh(sessionID: id))
    }

    // MARK: - Depth URL

    func testDepthMapURLNaming() {
        let id = UUID()
        XCTAssertEqual(
            storage.depthMapURL(index: 12, sessionID: id).lastPathComponent,
            "000012_depth.bin"
        )
        XCTAssertEqual(
            storage.depthMapURL(index: 12, sessionID: id).deletingLastPathComponent(),
            storage.framesDirectoryURL(sessionID: id)
        )
    }

    // MARK: - Archive

    func testCreateArchiveThrowsForUnknownSession() throws {
        try storage.prepareDirectories()
        XCTAssertThrowsError(try storage.createSessionArchive(id: UUID()))
    }

    // MARK: - File Name Sanitization

    func testSanitizedFileNameRemovesPathSeparators() {
        XCTAssertEqual(
            SessionStorage.sanitizedFileName("../../etc/passwd", fallback: "fallback"),
            "etcpasswd"
        )
    }

    func testSanitizedFileNameKeepsReadableNames() {
        XCTAssertEqual(
            SessionStorage.sanitizedFileName("リビング スキャン_01", fallback: "fallback"),
            "リビング スキャン_01"
        )
    }

    func testSanitizedFileNameUsesFallbackWhenEmpty() {
        XCTAssertEqual(SessionStorage.sanitizedFileName("///", fallback: "fallback"), "fallback")
        XCTAssertEqual(SessionStorage.sanitizedFileName("   ", fallback: "fallback"), "fallback")
    }

    func testSanitizedFileNameTruncatesLongNames() {
        let long = String(repeating: "あ", count: 200)
        XCTAssertEqual(SessionStorage.sanitizedFileName(long, fallback: "fallback").count, 60)
    }
}
