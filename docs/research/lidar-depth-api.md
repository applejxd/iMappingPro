# LiDAR 深度 API

## 概要

iPhone Pro / iPad Pro に搭載された LiDAR (Light Detection And Ranging) スキャナーは、
ARKit の `sceneDepth` および `smoothedSceneDepth` フレームセマンティクスを通じて
ピクセルごとの深度データを提供する。

## 深度データの取得

```swift
// 設定
let configuration = ARWorldTrackingConfiguration()
configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

// フレームから取得
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // 生深度マップ（高周波ノイズあり）
    if let sceneDepth = frame.sceneDepth {
        let depthMap: CVPixelBuffer = sceneDepth.depthMap
        let confidenceMap: CVPixelBuffer = sceneDepth.confidenceMap
    }
    
    // 平滑化深度マップ（時間的フィルタリング済み）
    if let smoothedDepth = frame.smoothedSceneDepth {
        let smoothedDepthMap: CVPixelBuffer = smoothedDepth.depthMap
    }
}
```

## 深度マップ仕様

| 項目 | 値 |
|---|---|
| ピクセル形式 | `kCVPixelFormatType_DepthFloat32` (32-bit float) |
| 単位 | メートル |
| 解像度 | ~256×192 px (iPhone 12 Pro 以降) |
| フレームレート | ~30 fps |
| 有効範囲 | 0.1m ～ 5.0m (室内環境) |

## 信頼度マップ

```swift
// ARConfidenceLevel の 3 段階
// .low    = 0  (信頼度低)
// .medium = 1  (信頼度中)
// .high   = 2  (信頼度高)

func processConfidence(from buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    
    for y in 0..<height {
        for x in 0..<width {
            let confidence = ptr[y * width + x]  // 0, 1, 2
            // confidence == 2: 高信頼度のみ使用
        }
    }
    
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
}
```

## RGBD データの同期

RGB フレームと深度マップは同一 `ARFrame` から取得するため、
タイムスタンプの同期は自動的に保証される。

```swift
struct RGBDFrame {
    let timestamp: TimeInterval
    let colorImage: CVPixelBuffer      // YCbCr420 (NV12)
    let depthMap: CVPixelBuffer        // Float32 meters
    let confidenceMap: CVPixelBuffer   // UInt8 (0/1/2)
    let cameraTransform: simd_float4x4
    let cameraIntrinsics: simd_float3x3
}
```

## 深度マップの座標系

- 深度マップは **カメラ座標系** における深度 (Z 値) を表す
- RGB と深度の解像度が異なるため、スケーリングが必要

```swift
// 深度マップのピクセル座標 → RGB 画像のピクセル座標への変換
// ARCamera.projectionMatrix を使用
func depthToRGBCoordinate(
    depthX: Int, depthY: Int,
    depthWidth: Int, depthHeight: Int,
    rgbWidth: Int, rgbHeight: Int
) -> CGPoint {
    let scaleX = Float(rgbWidth) / Float(depthWidth)
    let scaleY = Float(rgbHeight) / Float(depthHeight)
    return CGPoint(
        x: Double(Float(depthX) * scaleX),
        y: Double(Float(depthY) * scaleY)
    )
}
```

## カメラ内部パラメータ

```swift
// ARCamera.intrinsics は 3×3 行列 (fx, fy, cx, cy)
// | fx  0  cx |
// |  0 fy  cy |
// |  0  0   1 |
let intrinsics = frame.camera.intrinsics
let fx = intrinsics[0][0]
let fy = intrinsics[1][1]
let cx = intrinsics[2][0]
let cy = intrinsics[2][1]
```

## ファイル保存形式

### 深度マップの保存

```swift
// PNG 形式への変換（16-bit グレースケール）
func saveDepthAsPNG(depthMap: CVPixelBuffer, to url: URL) throws {
    // float32 → uint16 に変換 (最大深度 10m を 65535 に正規化)
    let maxDepth: Float = 10.0
    // CVPixelBuffer → CGImage → PNG
}

// バイナリ形式 (.bin) への保存 — 精度を保持
func saveDepthAsBinary(depthMap: CVPixelBuffer, to url: URL) throws {
    let data = depthMapToData(depthMap)
    try data.write(to: url)
}
```

### ファイル命名規則

```
session_<UUID>/
  frames/
    <index>_color.jpg    # RGB 画像
    <index>_depth.bin    # Float32 深度マップ
    <index>_conf.png     # 信頼度マップ
  poses.json             # 全フレームの6DOF姿勢
  metadata.json          # セッション情報
```

## 既知の制限事項

1. **屋外**: 強い直射日光下では精度が低下
2. **透明/反射物**: ガラス・鏡面は深度が不正確
3. **距離**: 5m 超えると精度が著しく低下
4. **動体**: 動いている物体の深度は不安定
5. **バッテリー消費**: LiDAR + 深度処理は高負荷
