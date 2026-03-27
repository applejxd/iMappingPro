# ADR-001: プロジェクト基盤 — Xcode プロジェクトと ARKit セッション

**ステータス**: 完了  
**日付**: 2026-03-27  
**リリース対象**: v0.1 (内部動作確認ビルド)

---

## コンテキスト

iPhone Pro の LiDAR を活用した RGBD+姿勢スキャンアプリを iOS 向けに開発する。  
最初のマイルストーンとして、ARKit セッションが起動し、カメラ映像を表示できる状態を目指す。

## 決定事項

### 1. 開発言語・フレームワーク

| 項目 | 決定 | 理由 |
|---|---|---|
| 言語 | Swift 5.9+ | Apple ファースト、型安全 |
| UI フレームワーク | SwiftUI | モダン宣言型 UI、iOS 16+ ターゲット |
| AR プレビュー | RealityKit (ARView) | LiDAR メッシュ表示のネイティブサポート |
| 最小 iOS バージョン | iOS 16.0 | SwiftUI の安定性、ARKit 6.0 |

### 2. デバイス要件

- LiDAR Scanner 搭載 iPhone (iPhone 12 Pro 以降)
- `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` でランタイムチェック
- 非対応デバイスには適切なエラーメッセージを表示

### 3. 権限・Info.plist

```xml
<key>NSCameraUsageDescription</key>
<string>ARKit によるスキャンのためにカメラを使用します。</string>
```

### 4. ARKit セッション設定 (基本)

```swift
let configuration = ARWorldTrackingConfiguration()
configuration.sceneReconstruction = .meshWithClassification
configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
configuration.planeDetection = [.horizontal, .vertical]
```

### 5. プロジェクト構造

```
iMappingPro/
├── iMappingPro.xcodeproj/
├── iMappingProApp.swift          # App エントリポイント
├── ContentView.swift             # ルートビュー (ナビゲーション分岐)
├── Models/
│   ├── ScanSession.swift         # セッションデータモデル
│   └── PoseFrame.swift           # 1フレームの姿勢+深度データ
├── ViewModels/
│   ├── ScanViewModel.swift       # スキャン操作ロジック
│   └── HistoryViewModel.swift    # 履歴管理ロジック
├── Views/
│   ├── ScanView.swift            # メインスキャン画面
│   ├── ARContainerView.swift     # ARView ラッパー
│   ├── HistoryView.swift         # 履歴一覧画面
│   └── SessionDetailView.swift   # スキャン確認画面
├── ARCore/
│   ├── ARSessionManager.swift    # ARSession のラッパー
│   └── DepthProcessor.swift      # 深度データ処理
└── Storage/
    └── SessionStorage.swift      # ファイル永続化
```

## 結果

### 実装内容 (v0.1)

- [x] Xcode プロジェクト作成
- [x] SwiftUI + RealityKit の基本セットアップ
- [x] `ARSessionManager`: ARKit セッションの開始・停止
- [x] `ARContainerView`: UIViewRepresentable で ARView を SwiftUI に統合
- [x] `ScanView`: カメラプレビュー表示（LiDAR メッシュ可視化付き）
- [x] LiDAR 非対応デバイスのエラーハンドリング
- [x] Info.plist カメラ権限設定

### 検証基準

1. iPhone Pro (物理デバイス) でアプリが起動する
2. カメラ映像が表示される
3. LiDAR メッシュのワイヤーフレームがオーバーレイ表示される
4. トラッキング状態がステータスラベルに表示される

## トレードオフ

- SceneKit ではなく RealityKit を採用: LiDAR メッシュ表示の実装が容易だが、低レベルなカスタマイズは SceneKit より難しい
- SwiftUI 採用: UIKit より宣言的で保守しやすいが、ARView との統合に UIViewRepresentable が必要
