# ADR-003: メインスキャン UI — プレビューとコントロール

**ステータス**: 完了  
**日付**: 2026-03-27  
**リリース対象**: v0.3 (UI 完成ビルド)

---

## コンテキスト

キャプチャパイプライン (v0.2) が動作する状態を踏まえ、
ユーザーが直感的に操作できる UI を実装する。

## 決定事項

### 1. 画面構成

```
ContentView
├── ScanView (メインスキャン画面)
│   ├── ARContainerView (フルスクリーン ARView)
│   ├── ステータスオーバーレイ (フレーム数、トラッキング状態)
│   └── コントロールパネル (Start/Stop, Save, Reset)
└── HistoryView (履歴一覧) — ADR-005 で実装
```

### 2. ScanView のレイアウト

```
┌─────────────────────────────────┐
│                                 │
│      ARView (カメラ + LiDAR     │
│         メッシュオーバーレイ)   │
│                                 │
│  [Tracking: Normal] [30 frames] │
├─────────────────────────────────┤
│  [  Start  ] [  Save  ] [Reset] │
└─────────────────────────────────┘
```

### 3. ボタンの状態遷移

```
状態: idle
  └→ [Start] タップ → ARKit セッション開始 → 状態: scanning

状態: scanning
  └→ [Stop]  タップ → データ収集一時停止 → 状態: paused
  └→ [Save]  タップ → 保存確認ダイアログ → 保存 → 状態: idle
  └→ [Reset] タップ → 確認ダイアログ → 全データ破棄 → 状態: idle

状態: paused
  └→ [Resume] タップ → データ収集再開 → 状態: scanning
  └→ [Save]   タップ → 保存 → 状態: idle
  └→ [Reset]  タップ → 確認ダイアログ → 状態: idle
```

### 4. トラッキング状態インジケータ

```swift
var trackingStatusColor: Color {
    switch trackingState {
    case .normal:              return .green
    case .limited:             return .yellow
    case .notAvailable:        return .red
    }
}

var trackingStatusText: String {
    switch trackingState {
    case .normal:              return "Tracking: Normal"
    case .limited(.initializing): return "Initializing..."
    case .limited(.excessiveMotion): return "Move Slower"
    case .limited(.insufficientFeatures): return "More Texture Needed"
    case .notAvailable:        return "Tracking Lost"
    }
}
```

### 5. 保存確認・名前入力

保存時にアラートで名前入力:
```swift
.alert("スキャンを保存", isPresented: $showingSaveAlert) {
    TextField("スキャン名", text: $sessionName)
    Button("保存") { viewModel.saveSession(name: sessionName) }
    Button("キャンセル", role: .cancel) {}
}
```

### 6. リセット確認

```swift
.alert("スキャンをリセット", isPresented: $showingResetAlert) {
    Button("リセット", role: .destructive) { viewModel.resetSession() }
    Button("キャンセル", role: .cancel) {}
} message: {
    Text("現在のスキャンデータをすべて破棄します。よろしいですか？")
}
```

### 7. リアルタイム統計表示

スキャン中のオーバーレイ:
- フレーム数 (取得済みキーフレーム数)
- 経過時間
- トラッキング状態
- 移動距離 (平行移動ノルム)

## 結果

### 実装内容 (v0.3)

- [x] `ScanView`: SwiftUI ビュー、コントロールパネル
- [x] `ARContainerView`: `UIViewRepresentable` で ARView を統合
- [x] ステータスオーバーレイ (フレーム数、状態、距離)
- [x] Start / Stop / Save / Reset ボタン
- [x] 保存名入力アラート
- [x] リセット確認アラート
- [x] LiDAR メッシュ可視化のオン/オフ切り替えボタン

### 検証基準

1. Start ボタンでスキャンが開始し、フレームカウンタが増加する
2. Stop ボタンでスキャンが一時停止する
3. Save ボタンで名前入力ダイアログが表示され、保存できる
4. Reset ボタンで確認後にデータがクリアされる
5. トラッキング状態が色付きラベルで表示される
6. LiDAR メッシュのワイヤーフレームが表示される

## トレードオフ

- フルスクリーン ARView + オーバーレイ: 最大視野角を確保
- SwiftUI アラートによる名前入力: TextFieldAlert より簡易だが iOS 16+ で安定動作
