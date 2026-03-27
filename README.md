# iMappingPro

iPhone Pro シリーズ向け 3D マッピングアプリ — ARKit + LiDAR による 6DOF 姿勢 + RGBD スキャン

## 概要

iMappingPro は iPhone Pro の LiDAR Scanner を活用した 3D スキャンアプリです。  
ARKit の Visual-Inertial Odometry により高精度な 6DOF 姿勢を取得し、  
RGBD フレームと同期して記録・管理します。

### 主な機能

- 🎯 **リアルタイム AR スキャン**: LiDAR メッシュのプレビュー表示
- 📍 **6DOF 姿勢記録**: 初期位置を原点とした相対姿勢 (平行移動 + クォータニオン)
- 📷 **RGBD 同期キャプチャ**: RGB (JPEG) + 深度 (Float32 binary) の時刻同期ペア
- 💾 **セッション管理**: 保存・リネーム・削除・共有
- 📊 **軌跡可視化**: XZ 平面への投影グラフ

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

---

## テスト手順

### 動作確認 (v0.1 〜 v1.0)

| # | 確認項目 | 期待動作 |
|---|---|---|
| 1 | アプリ起動 | カメラ権限を求めるダイアログが表示される |
| 2 | スキャン開始 | AR カメラ映像が表示され、LiDAR メッシュ (ワイヤーフレーム) がオーバーレイされる |
| 3 | トラッキング状態 | 上部ラベルに「トラッキング正常」(緑) が表示される |
| 4 | フレームカウント | デバイスを動かすとフレームカウンタが増加する |
| 5 | 保存 | 名前を入力して保存できる |
| 6 | 履歴確認 | 「履歴」タブに保存したセッションが表示される |
| 7 | 詳細確認 | セッションをタップするとフレームサムネイルと軌跡グラフが表示される |
| 8 | リネーム | 長押し → 「リネーム」で名前を変更できる |
| 9 | 削除 | スワイプ → 「削除」でセッションが消える |
| 10 | リセット | スキャン中に「リセット」でデータがクリアされる |

### ファイル確認

保存後、Xcode の `Files` タブまたは Files アプリで確認:

```
iMappingPro (App) > Documents > iMappingPro > sessions > <UUID> /
├── metadata.json
├── poses.json
└── frames/
    ├── 000000_color.jpg
    ├── 000000_depth.bin
    └── 000000_conf.png
```

---

## 出力データ形式

詳細は [docs/system/data-format.md](docs/system/data-format.md) を参照。

### poses.json (抜粋)

```json
{
  "session_id": "uuid",
  "frame_count": 100,
  "frames": [{
    "index": 0,
    "timestamp": 0.0,
    "translation": [0.0, 0.0, 0.0],
    "quaternion": [0.0, 0.0, 0.0, 1.0],
    "intrinsics": {"fx": 1440.0, "fy": 1440.0, "cx": 960.0, "cy": 720.0},
    "image_size": {"width": 1920, "height": 1440},
    "depth_size": {"width": 256, "height": 192}
  }]
}
```

---

## プロジェクト構造

```
iMappingPro/
├── README.md
├── AGENTS.md                      # 開発ルール・ADR 実行順序
├── docs/
│   ├── research/                  # 技術調査ドキュメント
│   ├── adr/                       # Architecture Decision Records
│   └── system/                    # システム設計ドキュメント
└── iMappingPro/
    ├── iMappingPro.xcodeproj/
    ├── iMappingProApp.swift
    ├── ContentView.swift
    ├── Models/                    # ScanSession, PoseFrame
    ├── ViewModels/                # ScanViewModel, HistoryViewModel
    ├── Views/                     # ScanView, HistoryView, SessionDetailView
    ├── ARCore/                    # ARSessionManager, DepthProcessor
    ├── Storage/                   # SessionStorage
    └── Info.plist
```

---

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/research/arkit-overview.md](docs/research/arkit-overview.md) | ARKit の仕様概要 |
| [docs/research/lidar-depth-api.md](docs/research/lidar-depth-api.md) | LiDAR 深度 API 詳細 |
| [docs/research/pose-estimation.md](docs/research/pose-estimation.md) | 姿勢推定の理論と実装 |
| [docs/research/related-libraries.md](docs/research/related-libraries.md) | 関連ライブラリ比較 |
| [docs/adr/ADR-001-project-foundation.md](docs/adr/ADR-001-project-foundation.md) | v0.1: プロジェクト基盤 |
| [docs/adr/ADR-002-capture-pipeline.md](docs/adr/ADR-002-capture-pipeline.md) | v0.2: キャプチャパイプライン |
| [docs/adr/ADR-003-scan-ui.md](docs/adr/ADR-003-scan-ui.md) | v0.3: スキャン UI |
| [docs/adr/ADR-004-persistence.md](docs/adr/ADR-004-persistence.md) | v0.4: セッション永続化 |
| [docs/adr/ADR-005-history-ui.md](docs/adr/ADR-005-history-ui.md) | v1.0: 履歴管理 UI |
| [docs/system/architecture.md](docs/system/architecture.md) | システムアーキテクチャ |
| [docs/system/data-format.md](docs/system/data-format.md) | データフォーマット仕様 |

---

## 開発状況

| ADR | リリース | ステータス |
|---|---|---|
| ADR-001 | v0.1 | ✅ 完了 |
| ADR-002 | v0.2 | ✅ 完了 |
| ADR-003 | v0.3 | ✅ 完了 |
| ADR-004 | v0.4 | ✅ 完了 |
| ADR-005 | v1.0 | ✅ 完了 |

> 次のステップ: iPhone Pro 実機でのビルド・動作確認
