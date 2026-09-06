import XCTest
@testable import iMappingProCore

/// フレーム品質情報の永続化と後方互換（B-5 / B-7）
final class FrameQualityTests: XCTestCase {

    // MARK: - isLowQuality

    func testNormalFrameIsNotLowQuality() {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: 0.9, confidenceMean: 1.8)
        XCTAssertFalse(quality.isLowQuality)
    }

    func testLimitedTrackingIsLowQuality() {
        let quality = FrameQuality(tracking: .limitedExcessiveMotion, depthValidRatio: 0.9)
        XCTAssertTrue(quality.isLowQuality)
    }

    func testTrailingFrameIsLowQuality() {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: 0.9, isTrailing: true)
        XCTAssertTrue(quality.isLowQuality)
    }

    func testSparseDepthIsLowQuality() {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: 0.05)
        XCTAssertTrue(quality.isLowQuality)
    }

    func testMissingDepthRatioIsNotLowQualityByItself() {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: nil)
        XCTAssertFalse(quality.isLowQuality)
    }

    func testMarkingTrailingKeepsOtherFields() {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: 0.8, confidenceMean: 1.5)
        let marked = quality.markingTrailing(true)
        XCTAssertTrue(marked.isTrailing)
        XCTAssertEqual(marked.tracking, .normal)
        XCTAssertEqual(marked.depthValidRatio, 0.8)
        XCTAssertEqual(marked.confidenceMean, 1.5)
    }

    // MARK: - Codable

    func testFrameQualityRoundTrip() throws {
        let original = FrameQuality(
            tracking: .limitedRelocalizing,
            depthValidRatio: 0.42,
            confidenceMean: 1.25,
            isTrailing: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FrameQuality.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFrameQualityJSONKeys() throws {
        let quality = FrameQuality(tracking: .normal, depthValidRatio: 0.5, confidenceMean: 2.0)
        let data = try JSONEncoder().encode(quality)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["tracking"] as? String, "normal")
        XCTAssertNotNil(json["depth_valid_ratio"])
        XCTAssertNotNil(json["confidence_mean"])
        XCTAssertNotNil(json["is_trailing"])
    }

    // MARK: - PoseFrameJSON

    func testPoseFrameJSONCarriesQuality() throws {
        let frame = makePoseFrame(
            quality: FrameQuality(tracking: .normal, depthValidRatio: 0.7, confidenceMean: 1.9)
        )
        let json = PoseFrameJSON(from: frame)
        XCTAssertEqual(json.quality?.tracking, .normal)
        XCTAssertEqual(json.quality?.depthValidRatio, 0.7)

        let data = try JSONEncoder().encode(json)
        let decoded = try JSONDecoder().decode(PoseFrameJSON.self, from: data)
        XCTAssertEqual(decoded.quality, json.quality)
    }

    /// 旧形式（quality キーなし）の poses.json も読み込めること
    func testPoseFrameJSONDecodesLegacyPayload() throws {
        let legacy = """
        {
          "index": 0,
          "timestamp": 1.5,
          "translation": [0.0, 0.0, 0.0],
          "quaternion": [0.0, 0.0, 0.0, 1.0],
          "intrinsics": { "fx": 1440.0, "fy": 1440.0, "cx": 960.0, "cy": 720.0 },
          "image_size": { "width": 1920, "height": 1440 },
          "depth_size": { "width": 256, "height": 192 }
        }
        """
        let decoded = try JSONDecoder().decode(
            PoseFrameJSON.self,
            from: Data(legacy.utf8)
        )
        XCTAssertNil(decoded.quality)
        XCTAssertEqual(decoded.index, 0)
        XCTAssertEqual(decoded.depthSize.width, 256)
    }

    // MARK: - Helpers

    private func makePoseFrame(quality: FrameQuality?) -> PoseFrame {
        PoseFrame(
            index: 0,
            timestamp: 1.5,
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            focalLengthX: 1440,
            focalLengthY: 1440,
            principalPointX: 960,
            principalPointY: 720,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192,
            quality: quality
        )
    }
}
