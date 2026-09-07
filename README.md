# iMappingPro

iPhone Pro シリーズ向け 3D マッピングアプリ — ARKit + LiDAR による 6DOF 姿勢 + RGBD スキャン

## 概要

iMappingPro は iPhone Pro の LiDAR Scanner を活用した 3D スキャンアプリです。  
ARKit の Visual-Inertial Odometry により高精度な 6DOF 姿勢を取得し、  
RGBD フレームと同期して記録・管理します。

### 主な機能

- 🎯 **リアルタイム AR スキャン**: LiDAR メッシュのプレビュー表示と、録画開始地点への座標軸表示 (表示専用・保存データには含まれません)
- 📍 **6DOF 姿勢記録**: 初期位置を原点とした相対姿勢 (平行移動 + クォータニオン)
- 📷 **RGBD 同期キャプチャ**: RGB (JPEG) + 深度 (Float32 binary) の時刻同期ペア
- 🧊 **統合メッシュ保存**: ARKit のシーン再構成メッシュを OBJ (`mesh.obj`) として書き出し
- 🎨 **色付き点群**: RGB + 深度から生成した点群を PLY (`points.ply`) として書き出し
- 💾 **セッション管理**: 保存・リネーム・削除・共有
- 📊 **軌跡可視化**: XZ 平面への投影グラフ
- 🖼️ **RGB / 深度プレビュー**: フレームサムネイルを RGB と深度カラーマップで切替表示
- 📦 **ダウンロード**: セッション一式 (ZIP) / メッシュ (OBJ) / 色付き点群 (PLY) / 姿勢データ (JSON) を共有

---

## 必要環境

| 項目 | 要件 |
|---|---|
| デバイス | iPhone 12 Pro 以降 (LiDAR Scanner 搭載) |
| iOS | 16.0 以上 |
| Xcode | 15.0 以上 |
| Swift | 5.9 以上 |

> ⚠️ LiDAR Scanner は iPhone Pro / iPad Pro にのみ搭載されています。  
> iPhone 標準モデルやシミュレータでは動作しません。

---

## ビルド手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/applejxd/iMappingPro.git
cd iMappingPro
```

### 2. Xcode でプロジェクトを開く

```bash
open iMappingPro/iMappingPro.xcodeproj
```

### 3. 署名の設定

1. Xcode で `iMappingPro` ターゲットを選択
2. `Signing & Capabilities` タブを開く
3. `Team` をご自身の Apple Developer アカウントに設定
4. `Bundle Identifier` を任意の値に変更 (例: `com.yourname.imappingpro`)

### 4. ビルド & 実行

1. 接続した iPhone Pro をターゲットデバイスとして選択
2. `⌘R` でビルド・実行

### CI ビルドチェック

プッシュ・プルリクエスト時に GitHub Actions で自動ビルドが実行されます。  
ビルドが通ることをコミットの条件としています。  
詳細は [`.github/workflows/build.yml`](.github/workflows/build.yml) を参照してください。

---

## テスト手順

### 動作確認 (v1.0)

| # | 確認項目 | 期待動作 |
|---|---|---|
| 1 | アプリ起動 | カメラ権限を求めるダイアログが表示される |
| 2 | スキャン開始 | AR カメラ映像が表示され、LiDAR メッシュ (ワイヤーフレーム) がオーバーレイされる |
| 2-a | 原点確認 | 録画開始地点に座標軸 (X: 赤 / Y: 緑 / Z: 青) が表示される。表示のみでメッシュ・点群には保存されない |
| 3 | トラッキング状態 | 上部ラベルに「トラッキング正常」(緑) が表示される |
| 4 | フレームカウント | デバイスを動かすとフレームカウンタが増加する |
| 5 | 保存 | 名前を入力して保存できる |
| 6 | 履歴確認 | 「履歴」タブに保存したセッションが表示される |
| 7 | 詳細確認 | セッションをタップするとメッシュ 3D プレビュー・フレームサムネイル・軌跡グラフが表示される |
| 7-a | メッシュ操作 | メッシュプレビューをドラッグで回転、ピンチで拡大縮小できる |
| 7-b | 深度プレビュー | 「深度」セグメントを選ぶとサムネイルが深度カラーマップに切り替わる |
| 7-c | ダウンロード | 右上のメニューから ZIP / OBJ / poses.json を共有できる |
| 8 | リネーム | 長押し → 「リネーム」で名前を変更できる |
| 9 | 削除 | スワイプ → 「削除」でセッションが消える |
| 10 | リセット | スキャン中に「リセット」でデータがクリアされる |

> ⚠️ LiDAR はシミュレータで動作しないため、実機テストが必須です。

### ファイル確認

保存後、Xcode の `Files` タブまたは Files アプリで確認:

```
iMappingPro (App) > Documents > iMappingPro > sessions > <UUID> /
├── metadata.json
├── poses.json
├── mesh.obj
├── points.ply
└── frames/
    ├── 000000_color.jpg
    ├── 000000_depth.bin
    └── 000000_conf.png
```

---

## 出力データ形式

詳細は [docs/system/data-format.md](docs/system/data-format.md) を参照。

座標系はスキャン開始時の縦持ち表示基準 (+X 右 / +Y 上 / -Z 撮影方向) です。
このため開始フレームの `quaternion` は Z 軸まわり -90° の回転になります。

### poses.json (抜粋)

```json
{
  "session_id": "uuid",
  "frame_count": 100,
  "frames": [{
    "index": 0,
    "timestamp": 0.0,
    "translation": [0.0, 0.0, 0.0],
    "quaternion": [0.0, 0.0, -0.7071, 0.7071],
    "intrinsics": {"fx": 1440.0, "fy": 1440.0, "cx": 960.0, "cy": 720.0},
    "image_size": {"width": 1920, "height": 1440},
    "depth_size": {"width": 256, "height": 192},
    "quality": {
      "tracking": "normal",
      "depth_valid_ratio": 0.93,
      "confidence_mean": 1.82,
      "is_trailing": false
    }
  }]
}
```

`quality` は後段処理でフレームを取捨選択するための付加情報です
(v1.2 以降。詳細は [docs/system/data-format.md](docs/system/data-format.md))。

### 姿勢の精度について

記録されるのは ARKit の VIO による**オドメトリ**です。ループ閉じ込みや大域バンドル調整は
行っていないため、長距離の再訪では数十 cm 規模のドリフトが残ることがあります。
厳密な位置合わせが必要な用途では、出力データを後段の SfM / SLAM
(COLMAP・Open3D など) に渡して最適化してください。

---

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/system/project-structure.md](docs/system/project-structure.md) | プロジェクト構造・開発状況 |
| [docs/system/architecture.md](docs/system/architecture.md) | システムアーキテクチャ・データフロー |
| [docs/system/data-format.md](docs/system/data-format.md) | データフォーマット仕様 |
| [CHANGELOG.md](CHANGELOG.md) | バージョン別変更履歴 |
