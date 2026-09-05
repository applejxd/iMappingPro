# ADR-009: メッシュ／深度のプレビューとダウンロード拡張

**ステータス**: 完了  
**日付**: 2026-09-05  
**リリース対象**: v1.1

---

## コンテキスト

v1.0 の履歴管理 UI (ADR-005) では、保存済みセッションから確認・共有できるのは
RGB フレームのサムネイルと 6DOF 軌跡のみだった。しかし本アプリは LiDAR による
シーン再構成 (`ARWorldTrackingConfiguration.sceneReconstruction`) を有効にしており、
スキャン中に得られる統合メッシュは保存も出力もされずに破棄されていた。

また深度マップ (`_depth.bin`) は保存されているものの、端末上で内容を確認する手段が無く、
スキャン品質の判断が RGB 画像だけに頼る状態だった。

共有機能も `poses.json` 単体のみで、RGBD やメッシュを含む一式を取り出せなかった。

## 決定事項

### 1. メッシュの保存形式は Wavefront OBJ

| 候補 | 採否 | 理由 |
|---|---|---|
| **OBJ (テキスト)** | **採用** | 実装が単純、SceneKit/ModelIO で直接プレビュー可、MeshLab・Open3D・trimesh などで広く読める |
| USDZ | 不採用 | Apple エコシステム外での取り回しが悪く、研究用途の後処理に向かない |
| PLY 点群 | 不採用 | メッシュを点群に落とすと面情報が失われる。OBJ の頂点をそのまま点群として利用できる |

- 出力先: `sessions/<UUID>/mesh.obj`
- 座標系は `poses.json` と同一（スキャン開始地点を原点とする相対座標系）に揃える。
  `ARMeshAnchor` はワールド座標系のため、`inverse(initialTransform) * anchor.transform` を適用する。
- 頂点数・面数は `metadata.json` (`meshVertexCount` / `meshFaceCount`) に任意フィールドとして記録し、
  一覧・詳細画面で表示する。既存セッションとの互換のため Optional とする。

### 2. メッシュ取得タイミング

`ARMeshAnchor` のジオメトリは Metal バッファ参照であり、セッション停止後は無効になり得る。
そのため保存操作 (`ScanViewModel.saveSession`) の冒頭、AR セッションが生きている状態で
`ARSessionManager.snapshotMeshChunks()` により純粋な Swift 配列 (`MeshChunk`) へコピーし、
OBJ 文字列化とファイル書き込みはバックグラウンドタスクで行う。

### 3. メッシュプレビュー

`MeshPreviewView` (SceneKit + ModelIO) で `mesh.obj` を読み込み、
`SCNView.allowsCameraControl` により回転・拡大縮小を可能にする。
読み込みはバックグラウンドで行い、失敗時はプレースホルダを表示する。

### 4. 深度プレビュー

`_depth.bin` を `DepthProcessor.decodeDepthBinary` でデコードし、
有効値の最小〜最大で正規化して「近距離=赤 → 遠距離=青」のカラーマップへ変換する。
無効値 (0 / NaN) は透明ピクセルとして扱う。
詳細画面のセグメントコントロールで RGB / 深度を切り替える。

### 5. ダウンロード（共有）対象

| メニュー | 対象 |
|---|---|
| セッション一式 (ZIP) | セッションディレクトリ全体 |
| メッシュ (OBJ) | `mesh.obj` |
| 姿勢データ (poses.json) | `poses.json` |

ZIP 生成は追加依存を避けるため `NSFileCoordinator` の `.forUploading` オプションを使用する
(iOS 標準機能のみで完結)。ZIP のファイル名はセッション名をサニタイズして使用し、
パス区切り文字などが含まれる場合は除去する。

## 検証基準

- [x] スキャン保存後に `sessions/<UUID>/mesh.obj` が生成される（LiDAR 実機）
- [x] 詳細画面でメッシュが 3D 表示され、回転・拡大縮小できる
- [x] 詳細画面で RGB / 深度サムネイルを切り替えられる
- [x] ダウンロードメニューから ZIP / OBJ / poses.json を共有できる
- [x] メッシュが無いセッションでもクラッシュせず「メッシュデータがありません」を表示する
- [x] `swift test` (Linux) が成功する

## 影響

- `ScanSession` にフィールドが増えるが Optional のため既存 `metadata.json` / `sessions.json` は読み込み可能
- OBJ はテキスト形式のため、大規模スキャンではファイルサイズが増える（面数に比例）
