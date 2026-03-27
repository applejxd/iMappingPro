# プロジェクト構造

## ディレクトリ構成

```
iMappingPro/
├── README.md                      # 使用方法・ビルド手順
├── CHANGELOG.md                   # バージョン別変更履歴
├── AGENTS.md                      # 開発ルール・ADR 実行順序
├── docs/
│   ├── research/                  # 技術調査ドキュメント
│   ├── adr/                       # Architecture Decision Records
│   └── system/                    # システム設計ドキュメント (本ファイル含む)
└── iMappingPro/
    ├── iMappingPro.xcodeproj/
    ├── iMappingProApp.swift        # @main エントリポイント
    ├── ContentView.swift           # ルートビュー (TabView)
    ├── Models/                    # データモデル (Codable 構造体)
    │   ├── ScanSession.swift      # セッションメタデータ
    │   ├── PoseFrame.swift        # 姿勢 + カメラパラメータ
    │   └── PosesContainer.swift   # poses.json ルートオブジェクト
    ├── ViewModels/                # ObservableObject (@MainActor)
    │   ├── ScanViewModel.swift    # スキャン状態管理
    │   └── HistoryViewModel.swift # 履歴 CRUD・共有
    ├── Views/                     # SwiftUI ビュー
    │   ├── ScanView.swift         # AR プレビュー + コントロール
    │   ├── ARContainerView.swift  # ARView ラッパー (UIViewRepresentable)
    │   ├── HistoryView.swift      # セッション一覧
    │   └── SessionDetailView.swift# 詳細 + 軌跡グラフ + サムネイル
    ├── ARCore/                    # ARKit セッション管理・深度処理
    │   ├── ARSessionManager.swift # ARSession ライフサイクル
    │   └── DepthProcessor.swift   # CVPixelBuffer 変換・キーフレーム選択
    ├── Storage/                   # ファイル永続化
    │   └── SessionStorage.swift   # FileManager ラッパー
    └── Info.plist                 # カメラ権限など
```

## 開発状況

| ADR | リリース | ステータス | 内容 |
|---|---|---|---|
| [ADR-001](../adr/ADR-001-project-foundation.md) | v0.1 | ✅ 完了 | プロジェクト基盤・ARKit セッション |
| [ADR-002](../adr/ADR-002-capture-pipeline.md) | v0.2 | ✅ 完了 | キャプチャパイプライン |
| [ADR-003](../adr/ADR-003-scan-ui.md) | v0.3 | ✅ 完了 | メインスキャン UI |
| [ADR-004](../adr/ADR-004-persistence.md) | v0.4 | ✅ 完了 | セッション永続化 |
| [ADR-005](../adr/ADR-005-history-ui.md) | v1.0 | ✅ 完了 | 履歴管理 UI |

## ドキュメント一覧

| ドキュメント | 内容 |
|---|---|
| [architecture.md](architecture.md) | システムアーキテクチャ・レイヤー構成・データフロー |
| [data-format.md](data-format.md) | 出力データフォーマット仕様 |
| [project-structure.md](project-structure.md) | 本ドキュメント (プロジェクト構造・開発状況) |
| [../research/arkit-overview.md](../research/arkit-overview.md) | ARKit の仕様概要 |
| [../research/lidar-depth-api.md](../research/lidar-depth-api.md) | LiDAR 深度 API 詳細 |
| [../research/pose-estimation.md](../research/pose-estimation.md) | 姿勢推定の理論と実装 |
| [../research/related-libraries.md](../research/related-libraries.md) | 関連ライブラリ比較 |
