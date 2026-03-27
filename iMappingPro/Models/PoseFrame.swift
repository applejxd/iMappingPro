import Foundation
#if canImport(simd)
import simd
#endif

/// 1フレームの姿勢・カメラパラメータ情報
struct PoseFrame: Codable, Identifiable {
    let id: UUID
    let index: Int
    let timestamp: TimeInterval

    // 相対姿勢（初期フレームを原点）
    let translationX: Float
    let translationY: Float
    let translationZ: Float
    let quaternionX: Float
    let quaternionY: Float
    let quaternionZ: Float
    let quaternionW: Float

    // カメラ内部パラメータ
    let focalLengthX: Float
    let focalLengthY: Float
    let principalPointX: Float
    let principalPointY: Float

    let imageWidth: Int
    let imageHeight: Int
    let depthWidth: Int
    let depthHeight: Int

    // MARK: - Computed Properties

    var translation: SIMD3<Float> {
        SIMD3<Float>(translationX, translationY, translationZ)
    }

    var quaternion: simd_quatf {
        simd_quatf(ix: quaternionX, iy: quaternionY, iz: quaternionZ, r: quaternionW)
    }

    /// 平行移動のノルム（メートル）
    var translationDistance: Float {
        simd_length(translation)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        index: Int,
        timestamp: TimeInterval,
        translation: SIMD3<Float>,
        quaternion: simd_quatf,
        focalLengthX: Float,
        focalLengthY: Float,
        principalPointX: Float,
        principalPointY: Float,
        imageWidth: Int,
        imageHeight: Int,
        depthWidth: Int,
        depthHeight: Int
    ) {
        self.id = id
        self.index = index
        self.timestamp = timestamp
        self.translationX = translation.x
        self.translationY = translation.y
        self.translationZ = translation.z
        self.quaternionX = quaternion.imag.x
        self.quaternionY = quaternion.imag.y
        self.quaternionZ = quaternion.imag.z
        self.quaternionW = quaternion.real
        self.focalLengthX = focalLengthX
        self.focalLengthY = focalLengthY
        self.principalPointX = principalPointX
        self.principalPointY = principalPointY
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
    }
}
