# CHANGELOG

iMappingPro の変更履歴です。  
[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) 形式に準拠しています。

---

## [1.0.0] - 2026-03-27

### Added

- **履歴管理 UI** (ADR-005)
  - `HistoryView`: 保存済みスキャンセッションの一覧表示 (List + NavigationLink)
  - `SessionDetailView`: フレームサムネイル表示 + XZ 平面への軌跡グラフ (`TrajectoryView`)
  - `FrameThumbnailView`: 非同期 JPEG サムネイル表示
  - スワイプ削除 (`.onDelete`)、コンテキストメニューによるリネーム・共有
  - `SessionRowView`: フレーム数・スキャン時間・推定容量・作成日時の表示

---

## [0.4.0] - 2026-03-27

### Added

- **セッション永続化** (ADR-004)
  - `SessionStorage`: FileManager を使った CRUD (作成/読込/削除/リネーム)
  - `ScanSession`: セッションメタデータの Codable モデル
  - `PoseFrame` / `PosesContainer`: 姿勢データの JSON シリアライズ
  - `sessions.json` によるセッション一覧インデックス管理
  - フレーム画像 (JPEG)・深度マップ (Float32 binary)・信頼度マップ (PNG) の保存
  - 並列書き込み (`withThrowingTaskGroup`) によるパフォーマンス最適化
  - Documents ディレクトリへの保存 (Files アプリ・iTunes 経由でアクセス可能)

---

## [0.3.0] - 2026-03-27

### Added

- **メインスキャン UI** (ADR-003)
  - `ScanView`: AR カメラプレビュー + Start/Stop/Save/Reset コントロールパネル
  - `ARContainerView`: `UIViewRepresentable` で `ARView` を SwiftUI に統合
  - トラッキング状態インジケーター (緑/黄/赤 のステータスバッジ)
  - フレームカウント・累積移動距離・経過時間のオーバーレイ表示
  - LiDAR メッシュ表示トグル
  - 保存ダイアログ (セッション名入力) / リセット確認ダイアログ

---

## [0.2.0] - 2026-03-27

### Added

- **キャプチャパイプライン** (ADR-002)
  - `DepthProcessor`: キーフレーム選択ロジック (移動距離・回転角・時間間隔による閾値判定)
  - `DepthProcessor.colorToJPEGData`: YCbCr CVPixelBuffer → JPEG Data 変換
  - `DepthProcessor.depthToBinary`: Float32 深度マップ → 独自バイナリ形式変換
  - `DepthProcessor.confidenceToData`: 信頼度マップ → PNG Data 変換
  - `ScanViewModel`: スキャン状態管理、フレームバッファリング、保存トリガー

---

## [0.1.0] - 2026-03-27

### Added

- **プロジェクト基盤** (ADR-001)
  - Xcode プロジェクト初期化 (Swift 5.9+、SwiftUI、iOS 16.0+)
  - `ARSessionManager`: ARKit セッションのライフサイクル管理
  - 相対 6DOF 姿勢計算 (初期フレームを原点とした `simd_float4x4` 逆変換)
  - LiDAR 非対応デバイスの検出とフォールバックエラー通知
  - `ARWorldTrackingConfiguration` セットアップ (`sceneReconstruction`, `frameSemantics`)
  - カメラ権限 (`NSCameraUsageDescription`) の `Info.plist` 設定
  - `ContentView`: TabView ルート (スキャン / 履歴)
