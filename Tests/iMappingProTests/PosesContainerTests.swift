import XCTest
@testable import iMappingProCore

final class PosesContainerTests: XCTestCase {

    // MARK: - PoseFrameJSON

    func testPoseFrameJSONInitFromPoseFrame() {
        let frame = PoseFrame(
            index: 3,
            timestamp: 1.5,
            translation: SIMD3<Float>(1.0, 2.0, 3.0),
            quaternion: simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9),
            focalLengthX: 1440.0,
            focalLengthY: 1440.0,
            principalPointX: 960.0,
            principalPointY: 720.0,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192
        )

        let json = PoseFrameJSON(from: frame)

        XCTAssertEqual(json.index, 3)
        XCTAssertEqual(json.timestamp, 1.5)
        XCTAssertEqual(json.translation, [1.0, 2.0, 3.0])
        XCTAssertEqual(json.quaternion[0], 0.1, accuracy: 0.001)
        XCTAssertEqual(json.quaternion[1], 0.2, accuracy: 0.001)
        XCTAssertEqual(json.quaternion[2], 0.3, accuracy: 0.001)
        XCTAssertEqual(json.quaternion[3], 0.9, accuracy: 0.001)
        XCTAssertEqual(json.intrinsics.fx, 1440.0)
        XCTAssertEqual(json.intrinsics.fy, 1440.0)
        XCTAssertEqual(json.intrinsics.cx, 960.0)
        XCTAssertEqual(json.intrinsics.cy, 720.0)
        XCTAssertEqual(json.imageSize.width, 1920)
        XCTAssertEqual(json.imageSize.height, 1440)
        XCTAssertEqual(json.depthSize.width, 256)
        XCTAssertEqual(json.depthSize.height, 192)
    }

    // MARK: - PoseFrameJSON Codable

    func testPoseFrameJSONCodableRoundTrip() throws {
        let frame = PoseFrame(
            index: 0,
            timestamp: 0.0,
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            focalLengthX: 1440.0,
            focalLengthY: 1440.0,
            principalPointX: 960.0,
            principalPointY: 720.0,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192
        )
        let original = PoseFrameJSON(from: frame)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PoseFrameJSON.self, from: data)

        XCTAssertEqual(decoded.index, original.index)
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.translation, original.translation)
        XCTAssertEqual(decoded.intrinsics.fx, original.intrinsics.fx)
        XCTAssertEqual(decoded.imageSize.width, original.imageSize.width)
        XCTAssertEqual(decoded.depthSize.height, original.depthSize.height)
    }

    // MARK: - PosesContainer Codable

    func testPosesContainerCodableRoundTrip() throws {
        let frames = (0..<3).map { i in
            PoseFrameJSON(from: PoseFrame(
                index: i,
                timestamp: Double(i) * 0.5,
                translation: SIMD3<Float>(Float(i), 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                focalLengthX: 1440, focalLengthY: 1440,
                principalPointX: 960, principalPointY: 720,
                imageWidth: 1920, imageHeight: 1440,
                depthWidth: 256, depthHeight: 192
            ))
        }
        let container = PosesContainer(
            sessionId: "test-session-id",
            frameCount: 3,
            frames: frames
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)

        let decoded = try JSONDecoder().decode(PosesContainer.self, from: data)

        XCTAssertEqual(decoded.sessionId, "test-session-id")
        XCTAssertEqual(decoded.frameCount, 3)
        XCTAssertEqual(decoded.frames.count, 3)
        XCTAssertEqual(decoded.frames[0].index, 0)
        XCTAssertEqual(decoded.frames[1].index, 1)
        XCTAssertEqual(decoded.frames[2].index, 2)
    }

    // MARK: - CodingKeys (snake_case)

    func testCodingKeysSnakeCase() throws {
        let container = PosesContainer(
            sessionId: "abc",
            frameCount: 0,
            frames: []
        )

        let data = try JSONEncoder().encode(container)
        let jsonString = String(data: data, encoding: .utf8)!

        // snake_case キーが使用されていることを確認
        XCTAssertTrue(jsonString.contains("\"session_id\""))
        XCTAssertTrue(jsonString.contains("\"frame_count\""))
        XCTAssertFalse(jsonString.contains("\"sessionId\""))
        XCTAssertFalse(jsonString.contains("\"frameCount\""))
    }

    func testPoseFrameJSONCodingKeysSnakeCase() throws {
        let frameJSON = PoseFrameJSON(from: PoseFrame(
            index: 0,
            timestamp: 0,
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            focalLengthX: 1440, focalLengthY: 1440,
            principalPointX: 960, principalPointY: 720,
            imageWidth: 1920, imageHeight: 1440,
            depthWidth: 256, depthHeight: 192
        ))

        let data = try JSONEncoder().encode(frameJSON)
        let jsonString = String(data: data, encoding: .utf8)!

        // image_size, depth_size が snake_case であること
        XCTAssertTrue(jsonString.contains("\"image_size\""))
        XCTAssertTrue(jsonString.contains("\"depth_size\""))
        XCTAssertFalse(jsonString.contains("\"imageSize\""))
        XCTAssertFalse(jsonString.contains("\"depthSize\""))
    }

    // MARK: - IntrinsicsJSON

    func testIntrinsicsJSONCodable() throws {
        let original = IntrinsicsJSON(fx: 1440.0, fy: 1440.0, cx: 960.0, cy: 720.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IntrinsicsJSON.self, from: data)

        XCTAssertEqual(decoded.fx, 1440.0)
        XCTAssertEqual(decoded.fy, 1440.0)
        XCTAssertEqual(decoded.cx, 960.0)
        XCTAssertEqual(decoded.cy, 720.0)
    }

    // MARK: - SizeJSON

    func testSizeJSONCodable() throws {
        let original = SizeJSON(width: 1920, height: 1440)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SizeJSON.self, from: data)

        XCTAssertEqual(decoded.width, 1920)
        XCTAssertEqual(decoded.height, 1440)
    }
}
