# ADR-007: テスタビリティ向上のためのアーキテクチャ改善

## ステータス

Accepted

## コンテキスト

ADR-006 のテスト戦略策定中に、以下のアーキテクチャ上の問題が発見された。

### 問題 1: ViewModel の依存関係ハードコード

`ScanViewModel` と `HistoryViewModel` が依存オブジェクトを直接インスタンス化しており、
テスト時にモックへの差し替えが不可能。

```swift
// 現状: ハードコードされた依存関係
final class ScanViewModel: ObservableObject {
    let sessionManager = ARSessionManager()
    private let depthProcessor = DepthProcessor()
    private let storage = SessionStorage()
}

final class HistoryViewModel: ObservableObject {
    private let storage = SessionStorage()
}
```

### 問題 2: クロスプラットフォーム非対応

全ソースファイルが iOS 固有フレームワーク（ARKit, UIKit, CoreVideo）に直接依存しており、
Linux 上での `swift test` によるユニットテスト実行が不可能。

### 問題 3: DepthProcessor の責務過多

`DepthProcessor` がキーフレーム選択（純粋ロジック）とピクセルバッファ処理（iOS固有）の
2つの独立した責務を持っている。テスト観点でこれらは分離すべき。

## 決定

### 1. 条件付きコンパイルによるクロスプラットフォーム対応

iOS 固有フレームワークの import を `#if canImport()` でガードする。

```swift
#if canImport(simd)
import simd
#endif
```

### 2. simd 互換層の追加

Linux でテスト可能にするため、`Platform/SimdCompat.swift` を追加。
`simd_quatf`, `simd_float4x4`, `simd_length()` 等の最小限の互換実装を提供。

### 3. SessionStorage のプロトコル化

テスト時にモック差し替え可能にするため、`SessionStorageProtocol` を導入。

```swift
protocol SessionStorageProtocol {
    func prepareDirectories() throws
    func loadAllSessions() throws -> [ScanSession]
    func saveSessionList(_ sessions: [ScanSession]) throws
    // ... 他のメソッド
}
```

### 4. HistoryViewModel の DI 対応

コンストラクタインジェクションにより、テスト時にモックストレージを注入可能にする。

```swift
final class HistoryViewModel: ObservableObject {
    private let storage: SessionStorageProtocol
    
    init(storage: SessionStorageProtocol = SessionStorage()) {
        self.storage = storage
    }
}
```

### 5. Package.swift の追加

Swift Package Manager でテスト実行するための `Package.swift` をルートに追加。
既存の Xcode プロジェクトには影響を与えない。

## 変更点

- 既存のソースファイルに `#if canImport()` ガードを追加（最小限）
- `iMappingPro/Platform/SimdCompat.swift` を新規作成
- `SessionStorage` に `SessionStorageProtocol` を追加
- `HistoryViewModel` のイニシャライザに DI パラメータを追加
- `Package.swift` をリポジトリルートに追加

## 影響

- Xcode プロジェクトでの iOS ビルドは変更なし
- Linux 上での `swift test` が可能になる
- 将来的なテスト追加が容易になる
