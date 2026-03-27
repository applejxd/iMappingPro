import Foundation

/// poses.json のルートオブジェクト
struct PosesContainer: Codable {
    let sessionId: String
    let frameCount: Int
    let frames: [PoseFrameJSON]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case frameCount = "frame_count"
        case frames
    }
}

/// poses.json 内の1フレーム（JSON シリアライズ向け）
struct PoseFrameJSON: Codable {
    let index: Int
    let timestamp: TimeInterval
    let translation: [Float]      // [tx, ty, tz]
    let quaternion: [Float]       // [qx, qy, qz, qw]
    let intrinsics: IntrinsicsJSON
    let imageSize: SizeJSON
    let depthSize: SizeJSON

    enum CodingKeys: String, CodingKey {
        case index, timestamp, translation, quaternion, intrinsics
        case imageSize = "image_size"
        case depthSize = "depth_size"
    }

    init(from frame: PoseFrame) {
        self.index = frame.index
        self.timestamp = frame.timestamp
        self.translation = [frame.translationX, frame.translationY, frame.translationZ]
        self.quaternion = [frame.quaternionX, frame.quaternionY, frame.quaternionZ, frame.quaternionW]
        self.intrinsics = IntrinsicsJSON(
            fx: frame.focalLengthX,
            fy: frame.focalLengthY,
            cx: frame.principalPointX,
            cy: frame.principalPointY
        )
        self.imageSize = SizeJSON(width: frame.imageWidth, height: frame.imageHeight)
        self.depthSize = SizeJSON(width: frame.depthWidth, height: frame.depthHeight)
    }
}

struct IntrinsicsJSON: Codable {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
}

struct SizeJSON: Codable {
    let width: Int
    let height: Int
}
