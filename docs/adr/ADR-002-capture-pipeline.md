# ADR-002: キャプチャパイプライン — 6DOF 姿勢 + RGBD フレーム取得

**ステータス**: 完了  
**日付**: 2026-03-27  
**リリース対象**: v0.2 (データ取得ビルド)

---

## コンテキスト

ARKit セッションが動作する状態 (v0.1) を踏まえ、各フレームから
相対 6DOF 姿勢と RGBD データを同期して取得するパイプラインを実装する。

## 決定事項

### 1. フレーム取得タイミング

ARKit の `session(_:didUpdate:)` コールバック (~30fps) でフレームを受信するが、
全フレームを保存するとストレージを大量消費するため、**キーフレーム選択**を行う。

```swift
// キーフレーム選択基準
struct KeyFrameSelector {
    let minTranslationDistance: Float = 0.05  // 5cm 以上移動
    let minRotationAngle: Float = 0.05        // ~3° 以上回転
    let maxFrameInterval: TimeInterval = 1.0  // 最大1秒間隔
}
```

### 2. データモデル

#### PoseFrame
```swift
struct PoseFrame: Codable, Identifiable {
    let id: UUID
    let index: Int
    let timestamp: TimeInterval
    // 相対姿勢 (初期フレームを原点)
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
}
```

#### ScanSession
```swift
struct ScanSession: Codable, Identifiable {
    let id: UUID
    var name: String
    let createdAt: Date
    var frameCount: Int
    var durationSeconds: Double
    // ディレクトリパス (Documents 配下)
    var directoryName: String
}
```

### 3. 深度データ保存形式

| 形式 | ファイル | 理由 |
|---|---|---|
| JPEG (品質 90) | `<N>_color.jpg` | サイズ・品質のバランス |
| Float32 バイナリ | `<N>_depth.bin` | 精度を完全保持 |
| UInt8 PNG | `<N>_conf.png` | 信頼度マップ (0/1/2) |

Float32 バイナリファイルのヘッダ:
```
[4 bytes] width (little-endian uint32)
[4 bytes] height (little-endian uint32)
[width*height*4 bytes] float32 depth values (row-major, meters)
```

### 4. 相対姿勢の計算

```swift
// セッション開始時の最初の有効フレームを原点として記録
// T_rel = T_initial^{-1} × T_current
func computeRelativePose(frame: ARFrame, initialTransform: simd_float4x4) -> (
    translation: SIMD3<Float>,
    quaternion: simd_quatf
) {
    let relativeMatrix = simd_inverse(initialTransform) * frame.camera.transform
    let translation = SIMD3<Float>(
        relativeMatrix.columns.3.x,
        relativeMatrix.columns.3.y,
        relativeMatrix.columns.3.z
    )
    let quaternion = simd_quaternion(relativeMatrix)
    return (translation, quaternion)
}
```

### 5. スレッドモデル

```
Main Thread:
  └── ARSession (delegateQueue: main) → UI 更新

Background Queue (captureQueue: DispatchQueue):
  └── フレームデータ処理
  └── 深度データ変換
  └── ファイル書き込み
```

- ARSession delegate は main queue で受信
- データ処理・書き込みは `captureQueue` (DispatchQueue(label: "capture", qos: .userInitiated)) で実行
- UI 更新は `DispatchQueue.main.async` で戻す

### 6. poses.json 形式

```json
{
  "session_id": "uuid-string",
  "created_at": "ISO8601",
  "frame_count": 100,
  "frames": [
    {
      "index": 0,
      "timestamp": 0.0,
      "translation": [0.0, 0.0, 0.0],
      "quaternion": [0.0, 0.0, 0.0, 1.0],
      "intrinsics": {
        "fx": 1440.0, "fy": 1440.0,
        "cx": 960.0,  "cy": 720.0
      },
      "image_size": {"width": 1920, "height": 1440},
      "depth_size": {"width": 256, "height": 192}
    }
  ]
}
```

## 結果

### 実装内容 (v0.2)

- [x] `ARSessionManager`: `ARSessionDelegate` 実装、フレームデータ取得
- [x] `DepthProcessor`: CVPixelBuffer → Data 変換、バイナリ書き込み
- [x] `ScanViewModel`: キーフレーム選択ロジック、相対姿勢計算
- [x] `PoseFrame` / `ScanSession`: Codable データモデル
- [x] バックグラウンドスレッドでの非同期書き込み

### 検証基準

1. スキャン中にフレームカウントが増加する
2. 保存後、Documents ディレクトリに正しい構造でファイルが生成される
3. `poses.json` が valid JSON で、フレーム数と一致する
4. `_depth.bin` のヘッダが正しい幅・高さを持つ
5. 深度値が 0.1〜5.0m の範囲内である

## トレードオフ

- キーフレーム選択を採用: ストレージ節約 vs. データ密度の減少
  → 閾値はユーザ設定で変更可能にする余地を残す
- JPEG 保存 (非可逆): サイズ削減 vs. 完全精度
  → 深度は可逆な float32 バイナリで保存するので許容範囲
