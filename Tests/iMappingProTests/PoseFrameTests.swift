import XCTest
@testable import iMappingProCore

final class PoseFrameTests: XCTestCase {

    // MARK: - Init

    func testInit() {
        let translation = SIMD3<Float>(1.0, 2.0, 3.0)
        let quaternion = simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9)

        let frame = PoseFrame(
            index: 5,
            timestamp: 1.5,
            translation: translation,
            quaternion: quaternion,
            focalLengthX: 1440.0,
            focalLengthY: 1440.0,
            principalPointX: 960.0,
            principalPointY: 720.0,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192
        )

        XCTAssertEqual(frame.index, 5)
        XCTAssertEqual(frame.timestamp, 1.5)
        XCTAssertEqual(frame.translationX, 1.0)
        XCTAssertEqual(frame.translationY, 2.0)
        XCTAssertEqual(frame.translationZ, 3.0)
        XCTAssertEqual(frame.quaternionX, 0.1, accuracy: 0.001)
        XCTAssertEqual(frame.quaternionY, 0.2, accuracy: 0.001)
        XCTAssertEqual(frame.quaternionZ, 0.3, accuracy: 0.001)
        XCTAssertEqual(frame.quaternionW, 0.9, accuracy: 0.001)
        XCTAssertEqual(frame.focalLengthX, 1440.0)
        XCTAssertEqual(frame.focalLengthY, 1440.0)
        XCTAssertEqual(frame.principalPointX, 960.0)
        XCTAssertEqual(frame.principalPointY, 720.0)
        XCTAssertEqual(frame.imageWidth, 1920)
        XCTAssertEqual(frame.imageHeight, 1440)
        XCTAssertEqual(frame.depthWidth, 256)
        XCTAssertEqual(frame.depthHeight, 192)
    }

    // MARK: - Computed Properties

    func testTranslation() {
        let frame = makePoseFrame(translation: SIMD3<Float>(1.0, 2.0, 3.0))
        let t = frame.translation
        XCTAssertEqual(t.x, 1.0)
        XCTAssertEqual(t.y, 2.0)
        XCTAssertEqual(t.z, 3.0)
    }

    func testQuaternion() {
        let q = simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9)
        let frame = makePoseFrame(quaternion: q)
        let result = frame.quaternion
        XCTAssertEqual(result.imag.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(result.imag.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(result.imag.z, 0.3, accuracy: 0.001)
        XCTAssertEqual(result.real, 0.9, accuracy: 0.001)
    }

    func testTranslationDistanceZero() {
        let frame = makePoseFrame(translation: SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(frame.translationDistance, 0.0, accuracy: 0.001)
    }

    func testTranslationDistanceUnit() {
        let frame = makePoseFrame(translation: SIMD3<Float>(3.0, 4.0, 0.0))
        XCTAssertEqual(frame.translationDistance, 5.0, accuracy: 0.001)
    }

    func testTranslationDistance3D() {
        let frame = makePoseFrame(translation: SIMD3<Float>(1.0, 2.0, 2.0))
        XCTAssertEqual(frame.translationDistance, 3.0, accuracy: 0.001)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = makePoseFrame(
            index: 10,
            timestamp: 2.5,
            translation: SIMD3<Float>(1.0, 2.0, 3.0),
            quaternion: simd_quatf(ix: 0.0, iy: 0.0, iz: 0.0, r: 1.0)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PoseFrame.self, from: data)

        XCTAssertEqual(original.index, decoded.index)
        XCTAssertEqual(original.timestamp, decoded.timestamp)
        XCTAssertEqual(original.translationX, decoded.translationX)
        XCTAssertEqual(original.translationY, decoded.translationY)
        XCTAssertEqual(original.translationZ, decoded.translationZ)
        XCTAssertEqual(original.quaternionX, decoded.quaternionX)
        XCTAssertEqual(original.quaternionY, decoded.quaternionY)
        XCTAssertEqual(original.quaternionZ, decoded.quaternionZ)
        XCTAssertEqual(original.quaternionW, decoded.quaternionW)
        XCTAssertEqual(original.focalLengthX, decoded.focalLengthX)
        XCTAssertEqual(original.imageWidth, decoded.imageWidth)
        XCTAssertEqual(original.depthWidth, decoded.depthWidth)
    }

    func testUniqueID() {
        let frame1 = makePoseFrame()
        let frame2 = makePoseFrame()
        XCTAssertNotEqual(frame1.id, frame2.id)
    }

    // MARK: - Helpers

    private func makePoseFrame(
        index: Int = 0,
        timestamp: TimeInterval = 0,
        translation: SIMD3<Float> = .zero,
        quaternion: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    ) -> PoseFrame {
        PoseFrame(
            index: index,
            timestamp: timestamp,
            translation: translation,
            quaternion: quaternion,
            focalLengthX: 1440.0,
            focalLengthY: 1440.0,
            principalPointX: 960.0,
            principalPointY: 720.0,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192
        )
    }
}
