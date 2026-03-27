import XCTest
@testable import iMappingProCore

final class SimdCompatTests: XCTestCase {

    // MARK: - simd_quatf

    func testQuatfInit() {
        let q = simd_quatf(ix: 0.1, iy: 0.2, iz: 0.3, r: 0.9)
        XCTAssertEqual(q.imag.x, 0.1, accuracy: 0.001)
        XCTAssertEqual(q.imag.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(q.imag.z, 0.3, accuracy: 0.001)
        XCTAssertEqual(q.real, 0.9, accuracy: 0.001)
    }

    func testQuatfVector() {
        let q = simd_quatf(ix: 1, iy: 2, iz: 3, r: 4)
        XCTAssertEqual(q.vector.x, 1)
        XCTAssertEqual(q.vector.y, 2)
        XCTAssertEqual(q.vector.z, 3)
        XCTAssertEqual(q.vector.w, 4)
    }

    // MARK: - simd_float4x4

    func testIdentityMatrix() {
        let m = simd_float4x4()
        XCTAssertEqual(m.columns.0, SIMD4<Float>(1, 0, 0, 0))
        XCTAssertEqual(m.columns.1, SIMD4<Float>(0, 1, 0, 0))
        XCTAssertEqual(m.columns.2, SIMD4<Float>(0, 0, 1, 0))
        XCTAssertEqual(m.columns.3, SIMD4<Float>(0, 0, 0, 1))
    }

    func testMatrixSubscript() {
        var m = simd_float4x4()
        m[3] = SIMD4<Float>(1, 2, 3, 1)
        XCTAssertEqual(m.columns.3, SIMD4<Float>(1, 2, 3, 1))
        XCTAssertEqual(m[3], SIMD4<Float>(1, 2, 3, 1))
    }

    // MARK: - simd_length

    func testSimdLength() {
        let v = SIMD3<Float>(3, 4, 0)
        XCTAssertEqual(simd_length(v), 5.0, accuracy: 0.001)
    }

    func testSimdLengthZero() {
        let v = SIMD3<Float>(0, 0, 0)
        XCTAssertEqual(simd_length(v), 0.0, accuracy: 0.001)
    }

    func testSimdLength3D() {
        let v = SIMD3<Float>(1, 2, 2)
        XCTAssertEqual(simd_length(v), 3.0, accuracy: 0.001)
    }

    // MARK: - simd_inverse

    func testInverseIdentity() {
        let identity = matrix_identity_float4x4
        let inv = simd_inverse(identity)

        // identity * identity^-1 = identity
        assertMatrixEqual(inv, identity, accuracy: 0.001)
    }

    func testInverseTranslation() {
        // 平行移動行列 T(2, 3, 4)
        var t = simd_float4x4()
        t[3] = SIMD4<Float>(2, 3, 4, 1)

        let inv = simd_inverse(t)

        // 逆行列は T(-2, -3, -4) のはず
        XCTAssertEqual(inv[3].x, -2, accuracy: 0.001)
        XCTAssertEqual(inv[3].y, -3, accuracy: 0.001)
        XCTAssertEqual(inv[3].z, -4, accuracy: 0.001)
    }

    func testInverseMultiplication() {
        // 任意の行列と逆行列の積 = 単位行列
        var m = simd_float4x4()
        m[0] = SIMD4<Float>(1, 0, 0, 0)
        m[1] = SIMD4<Float>(0, 0, -1, 0)
        m[2] = SIMD4<Float>(0, 1, 0, 0)
        m[3] = SIMD4<Float>(1, 2, 3, 1)

        let inv = simd_inverse(m)
        let product = inv * m

        assertMatrixEqual(product, matrix_identity_float4x4, accuracy: 0.001)
    }

    // MARK: - Matrix Multiplication

    func testMatrixMultiplicationIdentity() {
        let identity = matrix_identity_float4x4
        var m = simd_float4x4()
        m[3] = SIMD4<Float>(1, 2, 3, 1)

        let result = identity * m
        assertMatrixEqual(result, m, accuracy: 0.001)
    }

    // MARK: - Relative Transform (ARSessionManager logic)

    func testRelativeTransformFirstFrame() {
        // 初期フレーム → 単位行列を返す
        var initialTransform: simd_float4x4?

        // ARSessionManager.relativeTransform のロジックを再現
        var camera = simd_float4x4()
        camera[3] = SIMD4<Float>(5, 3, 2, 1)

        if initialTransform == nil {
            initialTransform = camera
        }
        let relative = simd_inverse(initialTransform!) * camera

        // 自分自身との相対 → 単位行列
        assertMatrixEqual(relative, matrix_identity_float4x4, accuracy: 0.001)
    }

    func testRelativeTransformMovement() {
        // 初期位置 (0,0,0) → (1,0,0) への移動
        var initial = simd_float4x4()
        initial[3] = SIMD4<Float>(0, 0, 0, 1)

        var current = simd_float4x4()
        current[3] = SIMD4<Float>(1, 0, 0, 1)

        let relative = simd_inverse(initial) * current

        // 相対的に x=1 の移動
        XCTAssertEqual(relative[3].x, 1.0, accuracy: 0.001)
        XCTAssertEqual(relative[3].y, 0.0, accuracy: 0.001)
        XCTAssertEqual(relative[3].z, 0.0, accuracy: 0.001)
    }

    func testRelativeTransformBothMoved() {
        // 初期位置 (2,3,4) → 現在位置 (5,3,4) → 相対 (3,0,0)
        var initial = simd_float4x4()
        initial[3] = SIMD4<Float>(2, 3, 4, 1)

        var current = simd_float4x4()
        current[3] = SIMD4<Float>(5, 3, 4, 1)

        let relative = simd_inverse(initial) * current

        XCTAssertEqual(relative[3].x, 3.0, accuracy: 0.001)
        XCTAssertEqual(relative[3].y, 0.0, accuracy: 0.001)
        XCTAssertEqual(relative[3].z, 0.0, accuracy: 0.001)
    }

    // MARK: - simd_quaternion (from matrix)

    func testQuaternionFromIdentity() {
        let q = simd_quaternion(matrix_identity_float4x4)
        // 単位行列 → 単位クォータニオン (0,0,0,1)
        XCTAssertEqual(q.imag.x, 0, accuracy: 0.001)
        XCTAssertEqual(q.imag.y, 0, accuracy: 0.001)
        XCTAssertEqual(q.imag.z, 0, accuracy: 0.001)
        XCTAssertEqual(abs(q.real), 1.0, accuracy: 0.001)
    }

    func testQuaternionFrom90DegRotationZ() {
        // Z軸90°回転: [[0,-1,0,0],[1,0,0,0],[0,0,1,0],[0,0,0,1]]
        let m = simd_float4x4(columns: (
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-1, 0, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))

        let q = simd_quaternion(m)
        // Z軸90°回転のクォータニオン: (0, 0, sin(45°), cos(45°)) ≈ (0, 0, 0.707, 0.707)
        let expectedSin = Float(0.7071)
        let expectedCos = Float(0.7071)
        XCTAssertEqual(abs(q.imag.x), 0, accuracy: 0.01)
        XCTAssertEqual(abs(q.imag.y), 0, accuracy: 0.01)
        XCTAssertEqual(abs(q.imag.z), expectedSin, accuracy: 0.01)
        XCTAssertEqual(abs(q.real), expectedCos, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func assertMatrixEqual(
        _ a: simd_float4x4,
        _ b: simd_float4x4,
        accuracy: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for col in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(
                    a[col][row], b[col][row],
                    accuracy: accuracy,
                    "Mismatch at [\(col)][\(row)]",
                    file: file,
                    line: line
                )
            }
        }
    }
}
