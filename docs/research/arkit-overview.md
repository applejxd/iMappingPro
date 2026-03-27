# ARKit 概要

## バージョンと対応 OS

| ARKit バージョン | iOS バージョン | 主な追加機能 |
|---|---|---|
| ARKit 1.0 | iOS 11 | 平面検出、光源推定 |
| ARKit 1.5 | iOS 11.3 | 垂直面検出、高解像度フレーム |
| ARKit 2.0 | iOS 12 | 環境テクスチャ、マルチユーザ、オブジェクト検出 |
| ARKit 3.0 | iOS 13 | MotionCapture、人物オクルージョン、複数フェイス追跡 |
| ARKit 3.5 | iOS 13.4 | LiDAR Scanner、シーン再構成 |
| ARKit 4.0 | iOS 14 | 位置アンカー、深度 API 改善 |
| ARKit 5.0 | iOS 15 | ロケーションアンカー強化、フェイストラッキング改善 |
| ARKit 6.0 | iOS 16 | 4K ビデオ、Motion Capture 改善 |

## ARWorldTrackingConfiguration

LiDAR スキャンに使用するメイン設定クラス。

```swift
let configuration = ARWorldTrackingConfiguration()
configuration.sceneReconstruction = .meshWithClassification  // メッシュ + 分類
configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
configuration.videoFormat = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing
session.run(configuration)
```

### 主要プロパティ

- **sceneReconstruction**: `.mesh` / `.meshWithClassification` — LiDAR によるメッシュ生成
- **frameSemantics**: `.sceneDepth` / `.smoothedSceneDepth` — 深度マップの取得
- **planeDetection**: 水平・垂直面の検出
- **environmentTexturing**: 環境マッピング

## ARFrame

各フレームに含まれるデータ:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let colorImage   = frame.capturedImage          // CVPixelBuffer (YCbCr)
    let depthMap     = frame.sceneDepth?.depthMap    // CVPixelBuffer (float32, メートル)
    let confidenceMap = frame.sceneDepth?.confidenceMap  // ARConfidenceLevel
    let cameraTransform = frame.camera.transform    // simd_float4x4 (4×4変換行列)
    let intrinsics   = frame.camera.intrinsics      // simd_float3x3 (カメラ内部パラメータ)
    let timestamp    = frame.timestamp              // TimeInterval
}
```

### カメラ座標系

- ARKit の座標系: **右手系**
  - X 軸: 右方向
  - Y 軸: 上方向
  - Z 軸: カメラから視聴者方向（手前）
- `camera.transform`: ワールド座標系におけるカメラの変換行列（4×4）
- 初期フレームの変換行列の逆行列を掛けることで相対姿勢に変換

## 6DOF 姿勢の計算

```swift
// 初期フレームの変換行列を記録
var initialTransform: simd_float4x4?

func relativeTransform(from frame: ARFrame) -> simd_float4x4 {
    let currentTransform = frame.camera.transform
    guard let initial = initialTransform else {
        initialTransform = currentTransform
        return matrix_identity_float4x4
    }
    // 相対変換 = 初期変換の逆行列 × 現在変換
    return simd_inverse(initial) * currentTransform
}
```

### 姿勢の表現

- **平行移動**: 変換行列の第4列 (columns.3.xyz) — メートル単位
- **回転**: 変換行列の左上3×3 → クォータニオンまたはオイラー角に変換
  ```swift
  let rotation = simd_quaternion(relativeTransform)
  ```

## ARMeshGeometry

LiDAR によって生成される 3D メッシュ:

```swift
func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
    for anchor in anchors {
        guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
        let geometry = meshAnchor.geometry
        let vertices = geometry.vertices         // MTLBuffer
        let faces    = geometry.faces            // MTLBuffer
        let normals  = geometry.normals          // MTLBuffer
        let classification = geometry.classification  // ARMeshClassification
    }
}
```

## パフォーマンス考慮事項

- LiDAR 深度マップは ~30fps で更新
- `smoothedSceneDepth` はノイズ低減のための時間的フィルタリングを適用
- メッシュ再構成は CPU/GPU リソースを消費するため、バックグラウンドスレッドでの処理を推奨
- 深度マップの解像度は通常 256×192 ピクセル (iPhone Pro)
- RGB フレームは 1920×1440 など高解像度で取得可能

## 対応デバイス

LiDAR Scanner を搭載した iPhone/iPad:
- iPhone 12 Pro / 12 Pro Max
- iPhone 13 Pro / 13 Pro Max
- iPhone 14 Pro / 14 Pro Max
- iPhone 15 Pro / 15 Pro Max
- iPad Pro (2020年以降)

確認方法:
```swift
ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
```
