import Foundation
#if canImport(simd)
import simd
#endif

/// スキャンデータの座標系定義と変換
///
/// ARKit の `ARCamera.transform` はランドスケープ（ホームボタンが右）を基準に定義されており、
/// 縦持ち（ポートレート）でデバイスを構えた場合は次の関係になる。
///
/// - カメラ +X: 画面の下方向
/// - カメラ +Y: 画面の右方向
/// - カメラ +Z: 画面手前（カメラの後ろ向き）
///
/// このためカメラ座標系をそのまま相対座標系に使うと、画面基準に対して Z 軸まわりに
/// 90° 回転した状態になり、メッシュや軌跡が左に 90° 倒れて見える。
///
/// 本アプリの相対座標系は「スキャン開始時のポートレート表示」を基準に定義する。
///
/// - +X: 画面の右方向
/// - +Y: 画面の上方向（縦持ちでは概ね鉛直上向き）
/// - +Z: 画面手前（カメラの後ろ向き）
enum CoordinateSystem {

    /// ARKit カメラ座標系 → ポートレート基準座標系への回転（Z 軸まわり -90°）
    ///
    /// `(x, y, z) -> (y, -x, z)`
    static let portraitAlignment = simd_float4x4(columns: (
        SIMD4<Float>(0, -1, 0, 0),
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))

    /// スキャン開始姿勢を原点とした、ポートレート基準の相対変換を計算する
    ///
    /// - Parameters:
    ///   - initial: スキャン開始時のカメラ姿勢（ワールド座標系）
    ///   - current: 現在のカメラ姿勢（ワールド座標系）
    /// - Returns: カメラローカル座標 → 相対座標系への変換行列
    static func relativeTransform(initial: simd_float4x4, current: simd_float4x4) -> simd_float4x4 {
        portraitAlignment * simd_inverse(initial) * current
    }

    /// 相対座標系の基準となる変換
    ///
    /// `simd_inverse(referenceTransform(initial:))` は
    /// `portraitAlignment * simd_inverse(initial)` と等価で、
    /// ワールド座標系のジオメトリ（`ARMeshAnchor` など）を相対座標系へ揃えるために使う。
    static func referenceTransform(initial: simd_float4x4) -> simd_float4x4 {
        initial * simd_inverse(portraitAlignment)
    }

    /// 平行移動＋クォータニオンから 4x4 変換行列を組み立てる
    ///
    /// `poses.json` に保存した相対姿勢から、点群の逆投影用に変換行列を復元する際に使う。
    static func transform(translation: SIMD3<Float>, quaternion: simd_quatf) -> simd_float4x4 {
        let q = quaternion.vector
        let length = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
        guard length > 0 else { return matrix_identity_float4x4 }
        let x = q.x / length, y = q.y / length, z = q.z / length, w = q.w / length

        let column0 = SIMD4<Float>(
            1 - 2 * (y * y + z * z),
            2 * (x * y + z * w),
            2 * (x * z - y * w),
            0
        )
        let column1 = SIMD4<Float>(
            2 * (x * y - z * w),
            1 - 2 * (x * x + z * z),
            2 * (y * z + x * w),
            0
        )
        let column2 = SIMD4<Float>(
            2 * (x * z + y * w),
            2 * (y * z - x * w),
            1 - 2 * (x * x + y * y),
            0
        )
        let column3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        return simd_float4x4(columns: (column0, column1, column2, column3))
    }

    /// `PoseFrame` から相対座標系のカメラ変換行列を復元する
    static func transform(from frame: PoseFrame) -> simd_float4x4 {
        transform(translation: frame.translation, quaternion: frame.quaternion)
    }
}
