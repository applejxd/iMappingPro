#if canImport(simd)
import simd
#else

// MARK: - Linux 用 simd 互換層
// swift test を Linux 上で実行するための最小限の simd 型・関数互換実装

import Foundation

// MARK: - simd_quatf

/// クォータニオン型（ix, iy, iz, r 形式）
public struct simd_quatf: Equatable, Sendable {
    public var vector: SIMD4<Float>

    public var real: Float { vector.w }
    public var imag: SIMD3<Float> { SIMD3(vector.x, vector.y, vector.z) }

    public init(ix: Float, iy: Float, iz: Float, r: Float) {
        self.vector = SIMD4(ix, iy, iz, r)
    }

    public init(vector: SIMD4<Float>) {
        self.vector = vector
    }
}

// MARK: - simd_float4x4

/// 4x4 行列型（column-major）
public struct simd_float4x4: Equatable, Sendable {
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    public init() {
        self.columns = (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public init(columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) {
        self.columns = columns
    }

    public subscript(column: Int) -> SIMD4<Float> {
        get {
            switch column {
            case 0: return columns.0
            case 1: return columns.1
            case 2: return columns.2
            case 3: return columns.3
            default: fatalError("Index out of range")
            }
        }
        set {
            switch column {
            case 0: columns.0 = newValue
            case 1: columns.1 = newValue
            case 2: columns.2 = newValue
            case 3: columns.3 = newValue
            default: fatalError("Index out of range")
            }
        }
    }

    public static func == (lhs: simd_float4x4, rhs: simd_float4x4) -> Bool {
        lhs.columns.0 == rhs.columns.0 &&
        lhs.columns.1 == rhs.columns.1 &&
        lhs.columns.2 == rhs.columns.2 &&
        lhs.columns.3 == rhs.columns.3
    }
}

// MARK: - 定数

/// 単位行列
public let matrix_identity_float4x4 = simd_float4x4()

// MARK: - 関数

/// SIMD3 ベクトルの長さ
public func simd_length(_ v: SIMD3<Float>) -> Float {
    (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
}

/// 4x4 行列の逆行列（余因子展開）
public func simd_inverse(_ m: simd_float4x4) -> simd_float4x4 {
    let a = m.columns.0
    let b = m.columns.1
    let c = m.columns.2
    let d = m.columns.3

    // 行列要素をフラットに展開
    let m00 = a.x, m01 = a.y, m02 = a.z, m03 = a.w
    let m10 = b.x, m11 = b.y, m12 = b.z, m13 = b.w
    let m20 = c.x, m21 = c.y, m22 = c.z, m23 = c.w
    let m30 = d.x, m31 = d.y, m32 = d.z, m33 = d.w

    // 余因子行列の計算
    let c00 = m11 * (m22 * m33 - m23 * m32) - m21 * (m12 * m33 - m13 * m32) + m31 * (m12 * m23 - m13 * m22)
    let c01 = -(m10 * (m22 * m33 - m23 * m32) - m20 * (m12 * m33 - m13 * m32) + m30 * (m12 * m23 - m13 * m22))
    let c02 = m10 * (m21 * m33 - m23 * m31) - m20 * (m11 * m33 - m13 * m31) + m30 * (m11 * m23 - m13 * m21)
    let c03 = -(m10 * (m21 * m32 - m22 * m31) - m20 * (m11 * m32 - m12 * m31) + m30 * (m11 * m22 - m12 * m21))

    let c10 = -(m01 * (m22 * m33 - m23 * m32) - m21 * (m02 * m33 - m03 * m32) + m31 * (m02 * m23 - m03 * m22))
    let c11 = m00 * (m22 * m33 - m23 * m32) - m20 * (m02 * m33 - m03 * m32) + m30 * (m02 * m23 - m03 * m22)
    let c12 = -(m00 * (m21 * m33 - m23 * m31) - m20 * (m01 * m33 - m03 * m31) + m30 * (m01 * m23 - m03 * m21))
    let c13 = m00 * (m21 * m32 - m22 * m31) - m20 * (m01 * m32 - m02 * m31) + m30 * (m01 * m22 - m02 * m21)

    let c20 = m01 * (m12 * m33 - m13 * m32) - m11 * (m02 * m33 - m03 * m32) + m31 * (m02 * m13 - m03 * m12)
    let c21 = -(m00 * (m12 * m33 - m13 * m32) - m10 * (m02 * m33 - m03 * m32) + m30 * (m02 * m13 - m03 * m12))
    let c22 = m00 * (m11 * m33 - m13 * m31) - m10 * (m01 * m33 - m03 * m31) + m30 * (m01 * m13 - m03 * m11)
    let c23 = -(m00 * (m11 * m32 - m12 * m31) - m10 * (m01 * m32 - m02 * m31) + m30 * (m01 * m12 - m02 * m11))

    let c30 = -(m01 * (m12 * m23 - m13 * m22) - m11 * (m02 * m23 - m03 * m22) + m21 * (m02 * m13 - m03 * m12))
    let c31 = m00 * (m12 * m23 - m13 * m22) - m10 * (m02 * m23 - m03 * m22) + m20 * (m02 * m13 - m03 * m12)
    let c32 = -(m00 * (m11 * m23 - m13 * m21) - m10 * (m01 * m23 - m03 * m21) + m20 * (m01 * m13 - m03 * m11))
    let c33 = m00 * (m11 * m22 - m12 * m21) - m10 * (m01 * m22 - m02 * m21) + m20 * (m01 * m12 - m02 * m11)

    let det = m00 * c00 + m01 * c01 + m02 * c02 + m03 * c03
    guard abs(det) > 1e-10 else { return matrix_identity_float4x4 }
    let invDet = 1.0 / det

    return simd_float4x4(columns: (
        SIMD4<Float>(c00, c10, c20, c30) * invDet,
        SIMD4<Float>(c01, c11, c21, c31) * invDet,
        SIMD4<Float>(c02, c12, c22, c32) * invDet,
        SIMD4<Float>(c03, c13, c23, c33) * invDet
    ))
}

/// 行列の乗算
public func * (lhs: simd_float4x4, rhs: simd_float4x4) -> simd_float4x4 {
    var result = simd_float4x4()
    for col in 0..<4 {
        for row in 0..<4 {
            var sum: Float = 0
            for k in 0..<4 {
                sum += lhs[k][row] * rhs[col][k]
            }
            result[col][row] = sum
        }
    }
    return result
}

/// 4x4 回転行列からクォータニオンを抽出する
public func simd_quaternion(_ m: simd_float4x4) -> simd_quatf {
    let m00 = m.columns.0.x
    let m11 = m.columns.1.y
    let m22 = m.columns.2.z
    let trace = m00 + m11 + m22

    if trace > 0 {
        let s = (trace + 1.0).squareRoot() * 2
        return simd_quatf(
            ix: (m.columns.1.z - m.columns.2.y) / s,
            iy: (m.columns.2.x - m.columns.0.z) / s,
            iz: (m.columns.0.y - m.columns.1.x) / s,
            r: 0.25 * s
        )
    } else if m00 > m11 && m00 > m22 {
        let s = (1.0 + m00 - m11 - m22).squareRoot() * 2
        return simd_quatf(
            ix: 0.25 * s,
            iy: (m.columns.1.x + m.columns.0.y) / s,
            iz: (m.columns.2.x + m.columns.0.z) / s,
            r: (m.columns.1.z - m.columns.2.y) / s
        )
    } else if m11 > m22 {
        let s = (1.0 + m11 - m00 - m22).squareRoot() * 2
        return simd_quatf(
            ix: (m.columns.1.x + m.columns.0.y) / s,
            iy: 0.25 * s,
            iz: (m.columns.2.y + m.columns.1.z) / s,
            r: (m.columns.2.x - m.columns.0.z) / s
        )
    } else {
        let s = (1.0 + m22 - m00 - m11).squareRoot() * 2
        return simd_quatf(
            ix: (m.columns.2.x + m.columns.0.z) / s,
            iy: (m.columns.2.y + m.columns.1.z) / s,
            iz: 0.25 * s,
            r: (m.columns.0.y - m.columns.1.x) / s
        )
    }
}

#endif
