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
| `ARContainerView` | UIViewRepresentable で ARView をラップ |
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
| `DepthProcessor` | CVPixelBuffer → Data 変換、キーフレーム選択 |

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

## スレッドモデル

```
Main Thread (UI)
  ├── ARSession (delegateQueue: main)
  │     └── session(_:didUpdate:) → ScanViewModel.sessionManager(_:didUpdate:relativePose:)
  │           └── [heavy work] → Task (Swift Concurrency)
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
    │ relativeTransform()
    │ delegate callback
    ▼
ScanViewModel.sessionManager(_:didUpdate:relativePose:)
    │ KeyFrameSelector.shouldCapture()
    │
    ├─→ [reject] → 次フレーム待機
    │
    └─→ [accept]
          │ DepthProcessor.colorToJPEGData()
          │ DepthProcessor.depthToBinary()
          │ DepthProcessor.confidenceToData()
          │
          ▼ append to buffer
          capturedFrames: [PoseFrame]
          pendingFrameData: [(color, depth, conf)]
          │
          ▼ UI update (@MainActor)
          frameCount, totalDistance

User → Save ボタン
    │
    ▼
ScanViewModel.saveSession(name:)
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
