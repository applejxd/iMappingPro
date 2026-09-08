# CHANGELOG

iMappingPro の変更履歴です。  
[Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) 形式に準拠しています。

---

## [Unreleased]

### Fixed

- **初回スキャンで「姿勢の不連続を検出しました」が出る問題**
  - `ARView.automaticallyConfigureSession` を `false` に変更。既定の `true` では
    アンカー追加や描画オプション変更のたびに ARView が自身の構成で
    `session.run(_:)` を呼び直し、ワールド原点や `frameSemantics` が上書きされる。
    録画開始と同時に原点の座標軸アンカーを追加するため、スキャン開始直後に
    姿勢が飛んでいた
  - 原点確定前に 0.5 秒ぶんの姿勢連続性を確認する `StartStabilityGate` を追加。
    ARKit がトラッキング開始直後にワールド原点を調整しても、その瞬間を
    原点に採用しないようにした
  - 不連続を検出したログにフレーム間の Δt / Δ位置 / Δ回転を出力するようにした
- **スキャン画面の「リセット」ラベルが折り返される問題**
  - 操作ボタンのラベルを 1 行に固定し、幅が足りない場合は縮小するようにした

### Changed

- **スキャン中のカクつきを改善**
  - RGB(JPEG) / 深度 / 信頼度マップのエンコードをメインスレッドから専用の直列キューへ移動
    （同時実行は 1 件までとし、間に合わない間はキーフレーム採用を見送って自動的に間引く）
  - `CIContext` をフレームごとに生成せずプロセス全体で共有
  - 信頼度マップの PNG 化と平均値算出を 1 回の走査に統合
  - `ARWorldTrackingConfiguration` から未使用の `.meshWithClassification` と
    `planeDetection` を外し、毎フレームの推論・解析コストを削減
  - 経過時間の発行を秒単位に変更し、AR プレビューを含むビュー全体の再評価を 1/10 に削減
  - `ARView.debugOptions` への再代入を変化時のみに限定
- **履歴画面の表示を高速化**
  - フレームサムネイルを ImageIO で縮小デコード（フル解像度のデコードを廃止）
  - `poses.json` のデコードをバックグラウンドへ移動
  - `_depth.bin` のデコードを画素単位の読み出しから一括コピーへ変更

---

## [1.2.0] - 2026-09-05

### Fixed

- **縦持ち撮影時の 90° 回転** (ADR-010)
  - RGB フレームの JPEG に EXIF Orientation (`.right`) を付与し、プレビューが正立するよう修正
  - 深度プレビュー画像も RGB と同じ向きに揃えた
  - 相対座標系を「スキャン開始時のポートレート表示」基準に変更し、
    メッシュプレビューの既定ビューと軌跡グラフ (XZ 平面) が正立するよう修正

### Added

- `CoordinateSystem`: ARKit カメラ座標系（ランドスケープ基準）→ 縦持ち基準の相対座標系変換
- **色付き点群** (`points.ply`)
  - `PointCloudExporter`: 深度画素の逆投影 + RGB サンプリング、PLY (binary little endian) の書き出し／読み込み
  - 詳細画面でメッシュ / 色付き点群を切り替えてプレビュー
  - 共有メニューに「色付き点群 (PLY)」を追加
- `MeshPreviewView`: バウンディングボックスから算出した正立の既定カメラを配置

### Changed

- **破壊的変更**: `poses.json` / `mesh.obj` の座標系が縦持ち基準になり、
  開始フレームの `quaternion` が `[0, 0, -0.7071, 0.7071]` になる（v1.1 以前のデータとは非互換）

---

## [1.1.0] - 2026-09-05

### Added

- **統合メッシュのエクスポートとプレビュー** (ADR-009)
  - `MeshExporter`: `ARMeshAnchor` → 相対座標系メッシュ変換・Wavefront OBJ 書き出し
  - セッション保存時に `mesh.obj` を出力し、頂点数・面数を `metadata.json` へ記録
  - `MeshPreviewView`: SceneKit + ModelIO による 3D メッシュプレビュー（回転・拡大縮小対応）
- **深度画像プレビュー**
  - `DepthProcessor.decodeDepthBinary` / `depthRGBAPixels` / `depthPreviewImage`:
    `_depth.bin` のデコードと近距離=赤・遠距離=青のカラーマップ可視化
  - `SessionDetailView`: RGB / 深度をセグメントコントロールで切り替え
- **ダウンロード対象の拡張**
  - セッションディレクトリ全体の ZIP 生成 (`SessionStorage.createSessionArchive`)
  - 共有メニュー: セッション一式 (ZIP) / メッシュ (OBJ) / 姿勢データ (poses.json)

### Changed

- `ScanSession` に `meshVertexCount` / `meshFaceCount` (任意) を追加

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
