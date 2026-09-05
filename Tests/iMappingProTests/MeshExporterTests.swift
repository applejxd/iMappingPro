import XCTest
@testable import iMappingProCore

final class MeshExporterTests: XCTestCase {

    private func makeChunk() -> MeshChunk {
        MeshChunk(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0),
            ],
            normals: [
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 0, 1),
                SIMD3<Float>(0, 0, 1),
            ],
            faces: [SIMD3<UInt32>(0, 1, 2)]
        )
    }

    // MARK: - Statistics

    func testStatisticsSumsChunks() {
        let stats = MeshExporter.statistics(of: [makeChunk(), makeChunk()])
        XCTAssertEqual(stats.vertexCount, 6)
        XCTAssertEqual(stats.faceCount, 2)
        XCTAssertFalse(stats.isEmpty)
    }

    func testStatisticsEmpty() {
        let stats = MeshExporter.statistics(of: [])
        XCTAssertEqual(stats.vertexCount, 0)
        XCTAssertEqual(stats.faceCount, 0)
        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: - OBJ Output

    func testObjStringContainsVerticesNormalsAndFaces() {
        let obj = MeshExporter.objString(chunks: [makeChunk()])
        XCTAssertTrue(obj.contains("v 0.0000 0.0000 0.0000"))
        XCTAssertTrue(obj.contains("v 1.0000 0.0000 0.0000"))
        XCTAssertTrue(obj.contains("vn 0.0000 0.0000 1.0000"))
        // OBJ のインデックスは 1 始まり
        XCTAssertTrue(obj.contains("f 1//1 2//2 3//3"))
        XCTAssertTrue(obj.contains("# vertices: 3"))
        XCTAssertTrue(obj.contains("# faces: 1"))
    }

    func testObjStringOffsetsIndicesAcrossChunks() {
        let obj = MeshExporter.objString(chunks: [makeChunk(), makeChunk()])
        XCTAssertTrue(obj.contains("f 1//1 2//2 3//3"))
        XCTAssertTrue(obj.contains("f 4//4 5//5 6//6"))
    }

    func testObjStringWithoutNormalsUsesPlainFaceFormat() {
        let chunk = MeshChunk(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0, 1, 0),
            ],
            faces: [SIMD3<UInt32>(0, 1, 2)]
        )
        let obj = MeshExporter.objString(chunks: [chunk])
        XCTAssertTrue(obj.contains("f 1 2 3"))
        XCTAssertFalse(obj.contains("//"))
    }

    func testObjDataIsUTF8Encodable() throws {
        let data = try XCTUnwrap(MeshExporter.objData(chunks: [makeChunk()]))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(text, MeshExporter.objString(chunks: [makeChunk()]))
    }

    func testEmptyChunkIsDetected() {
        XCTAssertTrue(MeshChunk(vertices: [], faces: []).isEmpty)
        XCTAssertTrue(MeshChunk(vertices: [SIMD3<Float>(0, 0, 0)], faces: []).isEmpty)
        XCTAssertFalse(makeChunk().isEmpty)
    }
}
