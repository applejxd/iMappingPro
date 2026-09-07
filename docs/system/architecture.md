# システムアーキテクチャ

## 概要

iMappingPro は iPhone Pro 搭載 LiDAR を活用した 3D スキャンアプリ。  
ARKit の VIO (Visual-Inertial Odometry) により 6DOF 姿勢を取得し、  
RGBD フレームと同期して記録・管理する。

## レイヤー構成

```
┌─────────────────────────────────────────────────────┐
│                    Views (SwiftUI)                   │
│  ScanView │ HistoryView │ SessionDetailView          │
├─────────────────────────────────────────────────────┤
│                  ViewModels (@MainActor)              │
│  ScanViewModel │ HistoryViewModel                    │
├──────────────────────┬──────────────────────────────┤
│  ARCore              │  Storage                      │
│  ARSessionManager    │  SessionStorage               │
│  DepthProcessor      │                               │
├──────────────────────┴──────────────────────────────┤
│                    Models (Codable)                   │
│  ScanSession │ PoseFrame │ PosesContainer            │
├─────────────────────────────────────────────────────┤
│             System Frameworks                        │
│  ARKit │ RealityKit │ CoreVideo │ SwiftUI             │
└─────────────────────────────────────────────────────┘
```

## コンポーネント詳細

### Views

| ビュー | 役割 |
|---|---|
| `ContentView` | TabView ルート (スキャン/履歴) |
| `ScanView` | AR プレビュー + Start/Stop/Save/Reset |
| `ARContainerView` | UIViewRepresentable で ARView をラップ・録画開始地点の座標軸を表示（表示専用） |
| `HistoryView` | セッション一覧 (List + NavigationLink) |
| `SessionDetailView` | フレームサムネイル + 軌跡グラフ |
| `TrajectoryView` | Canvas で XZ 平面投影の軌跡描画 |
| `FrameThumbnailView` | 非同期 JPEG サムネイル表示 |

### ViewModels

| VM | 役割 |
|---|---|
| `ScanViewModel` | スキャン状態管理、フレームキャプチャ、保存トリガー |
| `HistoryViewModel` | セッション一覧 CRUD、共有 |

### ARCore

| クラス | 役割 |
|---|---|
| `ARSessionManager` | ARSession ライフサイクル、相対姿勢計算 |
| `DepthProcessor` | CVPixelBuffer → Data 変換、`_depth.bin` のデコード・可視化、キーフレーム選択 |
| `MeshExporter` | ARMeshAnchor → 相対座標系メッシュ変換・Wavefront OBJ 書き出し |
| `CoordinateSystem` | ARKit カメラ座標系（ランドスケープ基準）→ 縦持ち基準相対座標系の変換定義 |
| `PointCloudExporter` | 深度 + RGB の逆投影による色付き点群生成・PLY 書き出し |

### Storage

| クラス | 役割 |
|---|---|
| `SessionStorage` | FileManager を使ったセッション CRUD |

### Models

| モデル | 役割 |
|---|---|
| `ScanSession` | セッションメタデータ (Codable) |
| `PoseFrame` | 1フレームの姿勢 + カメラパラメータ (Codable) |
| `PosesContainer` | poses.json のルートオブジェクト |
| `FrameQuality` | 1フレームの品質情報 (トラッキング状態・深度有効画素率など) |

## スレッドモデル

```
Main Thread (UI)
  ├── ARSession (delegateQueue: main)
  │     └── session(_:didUpdate:)
  │           ├── キーフレーム判定 (DepthProcessor)
  │           ├── ARFrame のバッファを Data へコピー
  │           └── CapturedFrame を @MainActor へ引き渡し
  └── SwiftUI ビュー更新 (@MainActor)

Swift Concurrency Task (background)
  ├── フレームデータ処理 (DepthProcessor)
  ├── JPEG/バイナリ書き込み (SessionStorage)
  └── poses.json 書き込み
```

## データフロー

```
ARKit (ARFrame)
    │
    ▼ session(_:didUpdate:) [~30fps]
ARSessionManager
    │ 開始ゲート (tracking == normal かつ深度あり)
    │ relativeTransform()
    │ DepthProcessor.evaluate()
    │
    ├─→ [skip]          → 次フレーム待機
    ├─→ [discontinuity] → 姿勢の飛びとして破棄
    │
    └─→ [capture]
          │ DepthProcessor.colorToJPEGData()
          │ DepthProcessor.depthToBinary()
          │ DepthProcessor.confidenceToData()
          │
          ▼ CapturedFrame (値型・Data のみ)
    │ delegate callback (@MainActor)
    ▼
ScanViewModel.sessionManager(_:didCapture:)
          │
          ▼ append to buffer
          capturedRecords: [CapturedFrame]
          │
          ▼ UI update (@MainActor)
          frameCount, totalDistance, missingDepthCount

User → Save ボタン
    │
    ▼
ScanViewModel.saveSession(name:)
    │ ScanViewModel.poseFrames(from:)  (index 整列・末尾フラグ付与)
    │ MeshExporter.objData()          (保存時に 1 回)
    │ PointCloudExporter.plyData()    (保存時に 1 回)
    │ async Task
    │ SessionStorage.createSessionDirectory()
    │ SessionStorage.saveColorImage() × N (parallel)
    │ SessionStorage.saveDepthMap() × N (parallel)
    │ SessionStorage.savePoses()
    │ SessionStorage.saveMetadata()
    │ SessionStorage.saveSessionList()
    ▼
HistoryView で表示
```
