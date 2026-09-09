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
| --- | --- |
| `ContentView` | TabView ルート (スキャン/履歴) |
| `ScanView` | AR プレビュー + Start/Stop/Save/Reset |
| `ARContainerView` | UIViewRepresentable で ARView をラップ・録画開始地点の座標軸を表示（計測中のみ・表示専用） |
| `HistoryView` | セッション一覧 (List + NavigationLink) |
| `SessionDetailView` | フレームサムネイル + 軌跡グラフ |
| `TrajectoryView` | Canvas で XZ 平面投影の軌跡描画 |
| `FrameThumbnailView` | 非同期 JPEG サムネイル表示 |

### ViewModels

| VM | 役割 |
| --- | --- |
| `ScanViewModel` | スキャン状態管理、フレームキャプチャ、保存トリガー |
| `HistoryViewModel` | セッション一覧 CRUD、共有 |

### ARCore

| クラス | 役割 |
| --- | --- |
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
| --- | --- |
| `ScanSession` | セッションメタデータ (Codable) |
| `PoseFrame` | 1フレームの姿勢 + カメラパラメータ (Codable) |
| `PosesContainer` | poses.json のルートオブジェクト |
| `FrameQuality` | 1フレームの品質情報 (トラッキング状態・深度有効画素率など) |

## スレッドモデル

```
session-delegate queue (serial, userInitiated)
  └── ARSession (delegateQueue: session-delegate)
        └── session(_:didUpdate:)   ※ 軽量処理のみ
              ├── キーフレーム判定 (DepthProcessor)
              └── ピクセルバッファ参照をエンコードキューへ引き渡し

Main Thread (UI)
  └── SwiftUI ビュー更新 (@MainActor)

frame-processing queue (serial, userInitiated)
  ├── JPEG / 深度バイナリ / 信頼度 PNG へのエンコード
  └── CapturedFrame を @MainActor へ受信順で引き渡し

Swift Concurrency Task (background)
  ├── JPEG/バイナリ書き込み (SessionStorage)
  └── poses.json 書き込み
```

> デリゲートは専用のシリアルキューで受ける。`delegateQueue` を指定しないと
> コールバックはメインキューに積まれ、メインスレッドが詰まった際に保留中の
> コールバックが `ARFrame` を保持し続ける。ARKit はこれを検知すると
> （"The delegate of ARSession is retaining N ARFrames" 警告）カメラと深度の
> 供給を止めるため、`sceneDepth` が nil になり `_depth.bin` / `_conf.png` が
> 対で欠落する。キャプチャ関連の可変状態はすべてこのキューに閉じ込め、
> 公開 API は用途に応じて `sync` / `async` でこのキューへ入る。

> エンコードはデリゲートキューを塞がないよう専用キューで行い、同時実行数は 1 に制限する。
> エンコードが間に合わない間はキーフレーム採用を見送るため、AR プレビューの
> フレームレートを保ったまま自動的に間引かれる。

## 記録開始フロー

ARKit はセッション開始直後にワールド原点を調整することがあり、その時点で記録を
始めると「姿勢の不連続」として検出されてしまう。以下の 4 段構えで回避する。

```
[開始] タップ
  │ ScanState = .preparing
  ├─ トラッキングが normal になるまで ARCoachingOverlayView で案内
  ├─ 3-2-1 カウントダウン（normal でない間はカウントを止めて測り直す）
  ├─ StartStabilityGate: 0.5 秒ぶん姿勢が連続したフレームを原点に採用
  └─ 記録開始 (ScanState = .scanning)
        └─ 開始直後 (先頭 30 キーフレーム以内) の不連続は
           エラーにせず原点を取り直す（最大 3 回・取得済みフレームは破棄）
```

- LiDAR メッシュのプレビュー (`.showSceneUnderstanding`) は計測中のみ有効にする
  （初期化中は GPU 負荷でトラッキングの収束が遅れるため）
- `ARView` は `automaticallyConfigureSession: false` で生成し、構成は
  `ARSessionManager` だけが管理する

## データフロー

```
ARKit (ARFrame)
    │
    ▼ session(_:didUpdate:) [~30fps]
ARSessionManager
    │ 開始ゲート (tracking == normal かつ深度あり + 0.5 秒の姿勢連続性)
    │ relativeTransform()
    │ DepthProcessor.evaluate()
    │   ※ 時刻が逆行・重複したフレーム (配送順の乱れ) は不連続にせず skip し、
    │      判定基準 (previousObservation) も巻き戻さない
    │
    ├─→ [skip]          → 次フレーム待機
    ├─→ [discontinuity] → 開始直後なら原点を取り直し、以降は破棄してキャプチャ停止
    │
    └─→ [capture]
          │ ※ エンコード中のフレームがある場合は見送り (自動間引き)
          │ ※ 深度が取れないフレームも見送る (color だけが増えるのを防ぐ)
          │
          ▼ frame-processing queue
          │ DepthProcessor.colorToJPEGData()
          │ DepthProcessor.depthToBinary()
          │ DepthProcessor.confidenceSummary()
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
    │ ScanViewModel.beginSavePrompt()  (名前入力中はキャプチャを停止)
    │   └─ キャンセル時は cancelSavePrompt() で再開
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
