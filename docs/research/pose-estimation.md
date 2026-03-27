# 姿勢推定 (Pose Estimation)

## ARKit の視覚的慣性オドメトリ (VIO)

ARKit は **Visual-Inertial Odometry (VIO)** により 6DOF の姿勢を推定する。

- **視覚**: バックカメラの RGB 映像から特徴点を追跡
- **慣性**: IMU (加速度計 + ジャイロスコープ) でドリフトを補正
- **LiDAR 補助**: iPhone Pro では深度データを用いてスケールドリフトを削減

## 座標系

### ARKit ワールド座標系

- ARKit はセッション開始時点のデバイス姿勢を基準とする **右手座標系** を使用
- 初期向き: Z 軸 = デバイスの後ろ方向、Y 軸 = 重力の逆方向
- 単位: メートル

### デバイス座標系

```
     Y (上)
     |
     |____X (右)
    /
   Z (手前, カメラ後方方向)
```

## 変換行列の構造

```swift
// simd_float4x4 — 列優先 (column-major)
// | r00 r01 r02 tx |
// | r10 r11 r12 ty |
// | r20 r21 r22 tz |
// |  0   0   0   1 |

let transform = frame.camera.transform

// 平行移動成分の抽出
let translation = SIMD3<Float>(
    transform.columns.3.x,
    transform.columns.3.y,
    transform.columns.3.z
)

// 回転成分の抽出 (クォータニオン)
let rotation = simd_quaternion(transform)

// オイラー角への変換 (ラジアン)
func eulerAngles(from matrix: simd_float4x4) -> SIMD3<Float> {
    let sy = sqrt(matrix.columns.0.x * matrix.columns.0.x +
                  matrix.columns.1.x * matrix.columns.1.x)
    let singular = sy < 1e-6
    
    var x, y, z: Float
    if !singular {
        x = atan2(matrix.columns.2.y, matrix.columns.2.z)
        y = atan2(-matrix.columns.2.x, sy)
        z = atan2(matrix.columns.1.x, matrix.columns.0.x)
    } else {
        x = atan2(-matrix.columns.1.z, matrix.columns.1.y)
        y = atan2(-matrix.columns.2.x, sy)
        z = 0
    }
    return SIMD3<Float>(x, y, z)
}
```

## 相対姿勢の計算

初期フレームを原点とした相対姿勢:

```swift
class PoseTracker {
    private var initialTransform: simd_float4x4?
    
    func reset() {
        initialTransform = nil
    }
    
    func relativePose(from frame: ARFrame) -> simd_float4x4 {
        let current = frame.camera.transform
        if initialTransform == nil {
            initialTransform = current
            return matrix_identity_float4x4
        }
        // T_rel = T_initial^{-1} × T_current
        return simd_inverse(initialTransform!) * current
    }
    
    func relativeTranslation(from frame: ARFrame) -> SIMD3<Float> {
        let rel = relativePose(from: frame)
        return SIMD3<Float>(rel.columns.3.x, rel.columns.3.y, rel.columns.3.z)
    }
}
```

## JSON シリアライズ形式

```json
{
  "frames": [
    {
      "index": 0,
      "timestamp": 1234567890.123,
      "translation": [0.0, 0.0, 0.0],
      "rotation_quaternion": [0.0, 0.0, 0.0, 1.0],
      "camera_intrinsics": {
        "fx": 1440.0, "fy": 1440.0,
        "cx": 960.0,  "cy": 720.0
      },
      "image_width": 1920,
      "image_height": 1440,
      "depth_width": 256,
      "depth_height": 192
    }
  ]
}
```

## トラッキング状態の監視

```swift
func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    switch camera.trackingState {
    case .normal:
        // 高精度トラッキング中 — データ収集に最適
        break
    case .notAvailable:
        // トラッキング不可 — データ収集停止
        break
    case .limited(let reason):
        switch reason {
        case .initializing:   break  // 初期化中
        case .relocalizing:   break  // 再ローカライズ中
        case .excessiveMotion: break // 動きが速すぎる
        case .insufficientFeatures: break // 特徴点不足
        @unknown default: break
        }
    }
}
```

## ARKit vs. 他の姿勢推定手法

| 手法 | 精度 | リアルタイム | 屋外対応 | 実装難易度 |
|---|---|---|---|---|
| ARKit VIO | ★★★★ | ○ | △ (制限あり) | 低 |
| ORB-SLAM3 | ★★★★★ | △ | ○ | 高 |
| OpenCV SfM | ★★★ | ✗ | ○ | 中 |
| Core Motion のみ | ★★ | ○ | ○ | 低 |
| RealityKit | ★★★★ | ○ | △ | 低 |

ARKit の VIO は iPhone Pro の LiDAR により通常の SLAM より高精度なスケール推定が可能。

## ドリフト対策

- **ループクロージャ**: ARKit は自動的に場所認識を行い、累積誤差を修正
- **重力方向の固定**: Y 軸は常に重力の逆方向に安定化
- **セッション長**: 長時間セッションではドリフトが累積するため、1 セッション 5 分以内推奨
