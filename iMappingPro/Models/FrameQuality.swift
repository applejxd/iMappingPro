import Foundation

/// キャプチャ時のトラッキング品質（ARKit 非依存の表現）
///
/// ARKit の `ARCamera.TrackingState` を永続化・テスト可能な形に写したもの。
enum FrameTrackingQuality: String, Codable, Equatable {
    case normal
    case limitedInitializing = "limited_initializing"
    case limitedRelocalizing = "limited_relocalizing"
    case limitedExcessiveMotion = "limited_excessive_motion"
    case limitedInsufficientFeatures = "limited_insufficient_features"
    case limitedUnknown = "limited_unknown"
    case notAvailable = "not_available"

    /// 姿勢をそのまま信頼してよい状態か
    var isReliable: Bool { self == .normal }
}

/// 1 フレームの品質情報（`poses.json` に出力される）
///
/// 後段の SfM / SLAM がフレームを取捨選択できるようにするための付加情報で、
/// 既存データとの互換のため `PoseFrame` では optional として扱う。
struct FrameQuality: Codable, Equatable {
    /// キャプチャ時のトラッキング状態
    let tracking: FrameTrackingQuality
    /// 深度マップの有効画素率 (0...1)。深度が無い場合は nil
    let depthValidRatio: Float?
    /// 信頼度マップの平均レベル (0...2)。信頼度が無い場合は nil
    let confidenceMean: Float?
    /// スキャン末尾の数フレームかどうか（保存操作時の手ブレが乗りやすい区間）
    let isTrailing: Bool

    /// 下流で除外を検討すべきフレームか
    var isLowQuality: Bool {
        if !tracking.isReliable { return true }
        if isTrailing { return true }
        if let ratio = depthValidRatio, ratio < FrameQuality.minDepthValidRatio { return true }
        return false
    }

    /// 有効画素率がこの値を下回るフレームは低品質として扱う
    static let minDepthValidRatio: Float = 0.2

    /// スキャン末尾のうち低品質フラグを立てるフレーム数
    static let trailingFrameCount: Int = 5

    enum CodingKeys: String, CodingKey {
        case tracking
        case depthValidRatio = "depth_valid_ratio"
        case confidenceMean = "confidence_mean"
        case isTrailing = "is_trailing"
    }

    init(
        tracking: FrameTrackingQuality,
        depthValidRatio: Float? = nil,
        confidenceMean: Float? = nil,
        isTrailing: Bool = false
    ) {
        self.tracking = tracking
        self.depthValidRatio = depthValidRatio
        self.confidenceMean = confidenceMean
        self.isTrailing = isTrailing
    }

    /// 末尾フラグだけを差し替えたコピーを返す
    func markingTrailing(_ trailing: Bool) -> FrameQuality {
        FrameQuality(
            tracking: tracking,
            depthValidRatio: depthValidRatio,
            confidenceMean: confidenceMean,
            isTrailing: trailing
        )
    }
}
