# ADR-005: 履歴管理 UI — 一覧・確認・リネーム・削除

**ステータス**: 完了  
**日付**: 2026-03-27  
**リリース対象**: v1.0 (製品完成ビルド)

---

## コンテキスト

永続化 (v0.4) が動作する状態を踏まえ、保存済みスキャンセッションを
管理するための UI (一覧・詳細確認・リネーム・削除) を実装し、v1.0 として完成させる。

## 決定事項

### 1. 画面構成

```
ContentView (TabView or NavigationSplitView)
├── Tab 1: ScanView (スキャン)
└── Tab 2: HistoryView (履歴)
             └→ NavigationLink → SessionDetailView (確認)
```

TabView を採用 (iPhone の標準的なナビゲーションパターン)。

### 2. HistoryView

```
┌─────────────────────────────────┐
│ 📋 スキャン履歴          [Edit] │
├─────────────────────────────────┤
│ ┌───────────────────────────┐   │
│ │ リビング 2024-01-01        │   │
│ │ 150 フレーム • 30秒 • 109MB│   │
│ └───────────────────────────┘   │
│ ┌───────────────────────────┐   │
│ │ 書斎 2024-01-02            │   │
│ │ 200 フレーム • 40秒 • 145MB│   │
│ └───────────────────────────┘   │
│                                 │
│         ← スキャンへ →          │
└─────────────────────────────────┘
```

- `List` + `NavigationLink` で実装
- スワイプで削除 (`.onDelete`)
- 長押し or コンテキストメニューでリネーム

### 3. SessionDetailView

```
┌─────────────────────────────────┐
│ ← リビング 2024-01-01    [Share]│
├─────────────────────────────────┤
│ 作成日時: 2024-01-01 10:00      │
│ フレーム: 150                   │
│ 時間:     30.5 秒               │
│ 容量:     ~109 MB               │
├─────────────────────────────────┤
│ [フレーム 0] [フレーム 1] ...   │ ← ScrollView
│ (サムネイル グリッド)           │
├─────────────────────────────────┤
│ 軌跡グラフ (XZ 平面投影)        │
└─────────────────────────────────┘
```

### 4. リネーム

コンテキストメニューから アラート経由で編集:

```swift
.contextMenu {
    Button("リネーム") { showRenameAlert = true }
    Button("削除", role: .destructive) { showDeleteAlert = true }
}
.alert("名前を変更", isPresented: $showRenameAlert) {
    TextField("セッション名", text: $editingName)
    Button("変更") { viewModel.rename(session: session, to: editingName) }
    Button("キャンセル", role: .cancel) {}
}
```

### 5. 削除

```swift
// スワイプ削除
.onDelete { indexSet in
    viewModel.deleteSessions(at: indexSet)
}

// 確認アラート付き削除
Button("削除", role: .destructive) {
    viewModel.deleteSession(session)
}
```

### 6. 軌跡の可視化

`SessionDetailView` でシンプルな 2D 軌跡グラフ (XZ 平面):

```swift
struct TrajectoryView: View {
    let frames: [PoseFrame]
    
    var body: some View {
        Canvas { context, size in
            let points = frames.map { frame -> CGPoint in
                // XZ 座標を正規化して Canvas サイズにマッピング
                CGPoint(x: ..., y: ...)
            }
            // パスを描画
            var path = Path()
            if let first = points.first {
                path.move(to: first)
                points.dropFirst().forEach { path.addLine(to: $0) }
            }
            context.stroke(path, with: .color(.blue), lineWidth: 2)
        }
    }
}
```

### 7. 共有 (Share)

`ShareLink` または `UIActivityViewController` でセッションディレクトリを ZIP して共有:

```swift
Button {
    shareSession(session)
} label: {
    Label("共有", systemImage: "square.and.arrow.up")
}
```

共有形式: セッションディレクトリを `.zip` に圧縮して共有

### 8. HistoryViewModel

```swift
@MainActor
class HistoryViewModel: ObservableObject {
    @Published var sessions: [ScanSession] = []
    @Published var errorMessage: String?
    
    func loadSessions()
    func deleteSession(_ session: ScanSession)
    func deleteSessions(at indexSet: IndexSet)
    func renameSession(_ session: ScanSession, to newName: String)
    func loadFrames(for session: ScanSession) -> [PoseFrame]
    func shareSession(_ session: ScanSession)
}
```

## 結果

### 実装内容 (v1.0)

- [x] `HistoryView`: セッション一覧 (List + NavigationLink)
- [x] `SessionDetailView`: フレームサムネイル、軌跡グラフ、メタデータ表示
- [x] `TrajectoryView`: Canvas を使った 2D 軌跡描画
- [x] `HistoryViewModel`: 全 CRUD 操作
- [x] スワイプ削除 + 確認アラート
- [x] コンテキストメニュー + リネームアラート
- [x] 共有機能 (ZIP エクスポート)
- [x] `ContentView`: TabView でスキャン・履歴を切り替え
- [x] タブバッジ (未保存スキャン存在時)

### 検証基準

1. 保存済みセッションが HistoryView にリストされる
2. スワイプ削除でセッションが削除され、ファイルも消える
3. コンテキストメニューからリネームができる
4. SessionDetailView でフレームサムネイルが表示される
5. 軌跡グラフが正しい形状を描画する
6. 共有ボタンで ZIP ファイルが生成され、共有シートが開く

## トレードオフ

- TabView vs NavigationSplitView: iPhone は TabView の方が一般的
- ZIP 共有: セッション全体を共有できるが、大きなセッションでは時間がかかる
- フレームサムネイル: 全フレームを一度に読み込むとメモリ圧迫 → LazyVGrid を使用
