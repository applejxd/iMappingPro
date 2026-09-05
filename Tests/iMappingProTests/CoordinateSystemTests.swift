import XCTest
@testable import iMappingProCore

final class CoordinateSystemTests: XCTestCase {

    private func transformed(_ v: SIMD3<Float>, by m: simd_float4x4) -> SIMD3<Float> {
        let result = m * SIMD4<Float>(v.x, v.y, v.z, 1)
        return SIMD3<Float>(result.x, result.y, result.z)
    }

    private func assertClose(
        _ lhs: SIMD3<Float>,
        _ rhs: SIMD3<Float>,
        accuracy: Float = 1e-5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Portrait Alignment

    /// ARKit カメラ座標系の +X（縦持ちでは画面下）が、相対座標系では -Y になる
    func testPortraitAlignmentMapsCameraXToScreenDown() {
        let mapped = transformed(SIMD3<Float>(1, 0, 0), by: CoordinateSystem.portraitAlignment)
        assertClose(mapped, SIMD3<Float>(0, -1, 0))
    }

    /// ARKit カメラ座標系の +Y（縦持ちでは画面右）が、相対座標系では +X になる
    func testPortraitAlignmentMapsCameraYToScreenRight() {
        let mapped = transformed(SIMD3<Float>(0, 1, 0), by: CoordinateSystem.portraitAlignment)
        assertClose(mapped, SIMD3<Float>(1, 0, 0))
    }

    /// 光軸方向 (-Z) は変わらない
    func testPortraitAlignmentKeepsOpticalAxis() {
        let mapped = transformed(SIMD3<Float>(0, 0, -1), by: CoordinateSystem.portraitAlignment)
        assertClose(mapped, SIMD3<Float>(0, 0, -1))
    }

    // MARK: - Relative Transform

    func testRelativeTransformAtStartHasZeroTranslation() {
        var initial = matrix_identity_float4x4
        initial.columns.3 = SIMD4<Float>(1, 2, 3, 1)

        let relative = CoordinateSystem.relativeTransform(initial: initial, current: initial)
        XCTAssertEqual(relative.columns.3.x, 0, accuracy: 1e-5)
        XCTAssertEqual(relative.columns.3.y, 0, accuracy: 1e-5)
        XCTAssertEqual(relative.columns.3.z, 0, accuracy: 1e-5)
    }

    /// 開始時に画面右方向（カメラ +Y）へ移動すると、相対座標系では +X 方向になる
    func testRelativeTransformRotatesTranslationIntoPortraitFrame() {
        let initial = matrix_identity_float4x4
        var current = matrix_identity_float4x4
        current.columns.3 = SIMD4<Float>(0, 0.5, 0, 1)

        let relative = CoordinateSystem.relativeTransform(initial: initial, current: current)
        assertClose(
            SIMD3<Float>(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z),
            SIMD3<Float>(0.5, 0, 0)
        )
    }

    /// 基準変換の逆行列は「ポートレート補正 × 初期姿勢の逆行列」と一致する
    func testReferenceTransformInverseMatchesRelativeConversion() {
        var initial = matrix_identity_float4x4
        initial.columns.3 = SIMD4<Float>(0.2, -0.4, 1.5, 1)

        let reference = CoordinateSystem.referenceTransform(initial: initial)
        let viaReference = simd_inverse(reference) * initial
        let direct = CoordinateSystem.relativeTransform(initial: initial, current: initial)

        for column in 0..<4 {
            XCTAssertEqual(viaReference[column].x, direct[column].x, accuracy: 1e-5)
            XCTAssertEqual(viaReference[column].y, direct[column].y, accuracy: 1e-5)
            XCTAssertEqual(viaReference[column].z, direct[column].z, accuracy: 1e-5)
            XCTAssertEqual(viaReference[column].w, direct[column].w, accuracy: 1e-5)
        }
    }

    // MARK: - Transform From Pose

    func testTransformFromIdentityQuaternion() {
        let matrix = CoordinateSystem.transform(
            translation: SIMD3<Float>(1, 2, 3),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        )
        assertClose(transformed(SIMD3<Float>(1, 0, 0), by: matrix), SIMD3<Float>(2, 2, 3))
    }

    /// Z 軸まわり 90° 回転（ポートレート補正と同じ回転）を再現できる
    func testTransformFromQuaternionMatchesPortraitAlignment() {
        let halfAngle = -Float.pi / 4  // -90° / 2
        let quaternion = simd_quatf(ix: 0, iy: 0, iz: sin(halfAngle), r: cos(halfAngle))
        let matrix = CoordinateSystem.transform(translation: .zero, quaternion: quaternion)

        assertClose(
            transformed(SIMD3<Float>(1, 0, 0), by: matrix),
            transformed(SIMD3<Float>(1, 0, 0), by: CoordinateSystem.portraitAlignment),
            accuracy: 1e-4
        )
        assertClose(
            transformed(SIMD3<Float>(0, 1, 0), by: matrix),
            transformed(SIMD3<Float>(0, 1, 0), by: CoordinateSystem.portraitAlignment),
            accuracy: 1e-4
        )
    }

    func testTransformFromPoseFrameUsesStoredPose() {
        let frame = PoseFrame(
            index: 0,
            timestamp: 0,
            translation: SIMD3<Float>(0.5, -0.25, 2),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            focalLengthX: 1440,
            focalLengthY: 1440,
            principalPointX: 960,
            principalPointY: 720,
            imageWidth: 1920,
            imageHeight: 1440,
            depthWidth: 256,
            depthHeight: 192
        )
        let matrix = CoordinateSystem.transform(from: frame)
        assertClose(
            SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
            SIMD3<Float>(0.5, -0.25, 2)
        )
    }
}
