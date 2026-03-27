# AGENTS.md — iMappingPro 実行ルール

## プロジェクト概要

iPhone Pro の LiDAR を活用した ARKit 3D スキャンアプリ。  
相対 6DOF 姿勢 + RGBD 画像を同期して記録し、スキャン履歴を管理する。

---

## 開発環境

| 項目 | バージョン |
|---|---|
| 言語 | Swift 5.9+ |
| Xcode | 15.0+ |
| iOS Deployment Target | 16.0 |
| 対象デバイス | iPhone Pro (LiDAR 搭載) |

---

## ADR 実行順序

ADRはリリース単位で切り出されている。**必ず順序通りに**実装すること。

| # | ADR | 内容 | リリース |
|---|---|---|---|
| 1 | ADR-001 | プロジェクト基盤・ARKit セッション | v0.1 |
| 2 | ADR-002 | キャプチャパイプライン | v0.2 |
| 3 | ADR-003 | メインスキャン UI | v0.3 |
| 4 | ADR-004 | セッション永続化 | v0.4 |
| 5 | ADR-005 | 履歴管理 UI | v1.0 |

---

## コーディング規約

### Swift スタイル

- **インデント**: スペース 4 つ
- **命名**:
  - クラス/構造体/列挙型: `UpperCamelCase`
  - メソッド/プロパティ/変数: `lowerCamelCase`
  - 定数: `lowerCamelCase` (Swift では `let` を使用)
- **アクセスコントロール**: 公開 API は `public`、内部は省略 (internal)、実装詳細は `private`
- **`@MainActor`**: UI に関わる ViewModel は `@MainActor` を付与
- **`async/await`**: 非同期処理は Swift Concurrency を優先 (DispatchQueue は最小限)

### SwiftUI 規約

- ビューは単一責任原則に従い、1ビュー = 1責務
- ビューのプレビュー (`#Preview`) を必ず追加
- `@StateObject` はビューの所有者に、`@ObservedObject` は受け取り側に使用
- 長い `body` は計算プロパティや `@ViewBuilder` メソッドで分割

### ARKit 規約

- ARKit 関連の処理は `ARCore/` 以下に集約
- セッション管理は `ARSessionManager` に一元化
- デリゲートメソッドはメインスレッドで受信し、重い処理はバックグラウンドへオフロード

---

## ファイル構造規約

```
iMappingPro/
├── iMappingProApp.swift        # @main エントリポイント
├── ContentView.swift           # ルートビュー (TabView)
├── Models/                     # データモデル (Codable 構造体)
├── ViewModels/                 # ObservableObject (@MainActor)
├── Views/                      # SwiftUI ビュー
├── ARCore/                     # ARKit セッション管理・深度処理
└── Storage/                    # ファイル永続化
```

---

## テスト・品質基準

### ビルド

```bash
xcodebuild -project iMappingPro.xcodeproj \
           -scheme iMappingPro \
           -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
           build
```

### 実機テスト

LiDAR はシミュレータで動作しないため、実機テストが必須:
- iPhone 12 Pro 以降のデバイスで動作確認
- テスト手順は README.md の「テスト手順」を参照

### コードレビュー観点

1. **メモリリーク**: ARSession, CVPixelBuffer の適切な解放
2. **スレッド安全性**: UI 更新は必ず Main Thread で実行
3. **エラーハンドリング**: do-catch を適切に使用し、ユーザに通知
4. **LiDAR 非対応デバイス**: フォールバック処理の確認

---

## セキュリティ・プライバシー

- カメラ使用目的を `Info.plist` の `NSCameraUsageDescription` に明記
- スキャンデータは **端末内のみ** に保存 (クラウド同期は v1.0 スコープ外)
- 共有機能は **ユーザの明示的な操作** のみで動作

---

## ドキュメント更新ルール

- 各 ADR 完了時に `docs/system/` 以下のシステムドキュメントを更新
- 各リリース完了時に `README.md` を更新
- 重要な設計変更は対応する ADR のステータスを `Superseded` に変更し、新 ADR を作成

---

## git コミット規約

```
<type>(<scope>): <description>

type: feat | fix | docs | refactor | test | chore
scope: arkit | ui | storage | models | adr | docs
```

例:
```
feat(arkit): ARSessionManager のキャプチャパイプライン実装
docs(adr): ADR-003 スキャン UI の決定事項追加
fix(storage): SessionStorage の空きストレージ確認バグ修正
```

---

## 行動完了基準

- [ ] ADR-001 〜 ADR-005 の実装が完了
- [ ] 各 ADR の「検証基準」が満たされていることを確認
- [ ] README.md が最新の状態
- [ ] docs/system/ のシステムドキュメントが最新
- [ ] ビルドエラーがない状態 (実機ビルドが望ましい)
