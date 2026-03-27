# ADR-006: テスト戦略

## ステータス

Accepted

## コンテキスト

iMappingPro の全機能に対してテストカバレッジを追加する必要がある。
LiDAR / ARKit は実機（iPhone Pro）でのみ動作するため、テスト可能な範囲を明確にし、
モック追加でカバーできる範囲を最大限実装する。

## 全機能テスト一覧と実機不要テスト可否判定

### Models

| テスト項目 | 実機不要 | モック不要 | 備考 |
|---|:---:|:---:|---|
| ScanSession: init デフォルト値 | ✅ | ✅ | 純粋な構造体 |
| ScanSession: formattedDate | ✅ | ✅ | DateFormatter のみ |
| ScanSession: formattedDuration (秒) | ✅ | ✅ | 純粋計算 |
| ScanSession: formattedDuration (分秒) | ✅ | ✅ | 純粋計算 |
| ScanSession: estimatedFileSizeMB | ✅ | ✅ | 純粋計算 |
| ScanSession: Codable エンコード/デコード | ✅ | ✅ | Foundation のみ |
| ScanSession: directoryName デフォルト (UUID) | ✅ | ✅ | 純粋ロジック |
| SessionsContainer: Codable | ✅ | ✅ | Foundation のみ |
| PoseFrame: init と stored properties | ✅ | ✅ | simd 互換層必要 |
| PoseFrame: translation 計算プロパティ | ✅ | ✅ | SIMD3 演算 |
| PoseFrame: quaternion 計算プロパティ | ✅ | ✅ | simd_quatf 互換必要 |
| PoseFrame: translationDistance | ✅ | ✅ | simd_length 互換必要 |
| PoseFrame: Codable エンコード/デコード | ✅ | ✅ | Foundation + simd 互換 |
| PoseFrameJSON: init(from: PoseFrame) | ✅ | ✅ | 変換ロジック |
| PoseFrameJSON: Codable | ✅ | ✅ | Foundation のみ |
| IntrinsicsJSON: Codable | ✅ | ✅ | Foundation のみ |
| SizeJSON: Codable | ✅ | ✅ | Foundation のみ |
| PosesContainer: Codable + CodingKeys | ✅ | ✅ | snake_case マッピング |

### Storage

| テスト項目 | 実機不要 | モック不要 | 備考 |
|---|:---:|:---:|---|
| SessionStorage: prepareDirectories | ✅ | ✅ | FileManager (シミュレータ/Linux) |
| SessionStorage: saveSessionList / loadAllSessions | ✅ | ✅ | JSON ファイル I/O |
| SessionStorage: loadAllSessions (ファイルなし) | ✅ | ✅ | 空配列を返す |
| SessionStorage: createSessionDirectory | ✅ | ✅ | ディレクトリ作成 |
| SessionStorage: saveMetadata | ✅ | ✅ | JSON 書き込み |
| SessionStorage: savePoses / loadPoses | ✅ | ✅ | PoseFrame の往復変換 |
| SessionStorage: saveColorImage | ✅ | ✅ | バイナリ書き込み |
| SessionStorage: saveDepthMap | ✅ | ✅ | バイナリ書き込み |
| SessionStorage: saveConfidenceMap | ✅ | ✅ | バイナリ書き込み |
| SessionStorage: colorImageURL パス生成 | ✅ | ✅ | URL 文字列 |
| SessionStorage: deleteSession | ✅ | ✅ | ファイル削除 + リスト更新 |
| SessionStorage: renameSession | ✅ | ✅ | メタデータ + リスト更新 |
| SessionStorage: renameSession (存在しない ID) | ✅ | ✅ | エラーハンドリング |

### ARCore

| テスト項目 | 実機不要 | モック不要 | 備考 |
|---|:---:|:---:|---|
| DepthProcessor: shouldCapture (初回) | ✅ | ✅ | 純粋ロジック (simd 互換必要) |
| DepthProcessor: shouldCapture (時間閾値) | ✅ | ✅ | 純粋ロジック |
| DepthProcessor: shouldCapture (移動閾値) | ✅ | ✅ | 純粋ロジック |
| DepthProcessor: shouldCapture (回転閾値) | ✅ | ✅ | 純粋ロジック |
| DepthProcessor: shouldCapture (閾値未満) | ✅ | ✅ | 純粋ロジック |
| DepthProcessor: updateLast / reset | ✅ | ✅ | 状態管理 |
| DepthProcessor: depthToBinary | ❌ | ❌ | CVPixelBuffer 実機必要 |
| DepthProcessor: confidenceToData | ❌ | ❌ | CVPixelBuffer 実機必要 |
| DepthProcessor: colorToJPEGData | ❌ | ❌ | CVPixelBuffer + CIContext |
| ARSessionManager: relativeTransform (初回) | ✅ | ✅ | simd_float4x4 互換必要 |
| ARSessionManager: relativeTransform (相対計算) | ✅ | ✅ | 行列演算 |
| ARSessionManager: startCapture/stopCapture 状態 | ✅ | ✅ | bool フラグ |
| ARSessionManager: isLiDARSupported | ❌ | ❌ | ARKit 実機必要 |
| ARSessionManager: startSession | ❌ | ❌ | ARKit 実機必要 |
| ARSessionManager: ARSessionDelegate | ❌ | ✅ (モック必要) | ARFrame モック困難 |
| TrackingState: displayText | ❌ | ❌ | ARCamera.TrackingState.Reason 依存 |
| TrackingState: isUsable | ❌ | ❌ | パターンマッチだが enum に ARKit 依存 |

### ViewModels

| テスト項目 | 実機不要 | モック不要 | 備考 |
|---|:---:|:---:|---|
| ScanViewModel: 状態遷移 (idle→scanning) | ❌ | ❌ | ARSessionManager.startSession() 呼出 |
| ScanViewModel: 状態遷移 (scanning→paused) | ❌ | ❌ | ARSessionManager 依存 |
| ScanViewModel: saveSession (フレームなし) | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| ScanViewModel: saveSession (正常) | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| HistoryViewModel: loadSessions | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| HistoryViewModel: deleteSession | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| HistoryViewModel: renameSession | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| HistoryViewModel: renameSession (空白) | ✅ | ✅ | 早期リターン |
| HistoryViewModel: shareSession (ファイルあり) | ✅ | ✅ (モック必要) | DI リファクタリング必要 |
| HistoryViewModel: shareSession (ファイルなし) | ✅ | ✅ (モック必要) | DI リファクタリング必要 |

### Views (UI テスト)

| テスト項目 | 実機不要 | モック不要 | 備考 |
|---|:---:|:---:|---|
| ScanView: レイアウト | ❌ | ❌ | ARView + SwiftUI |
| HistoryView: 空状態表示 | ❌ | ❌ | SwiftUI プレビューで目視確認 |
| HistoryView: リスト表示 | ❌ | ❌ | SwiftUI プレビューで目視確認 |
| SessionDetailView: メタデータ表示 | ❌ | ❌ | SwiftUI プレビューで目視確認 |
| ARContainerView: メッシュ切り替え | ❌ | ❌ | ARView 実機必要 |

## 決定

### 実装するテスト（モック追加で対応可能な範囲）

1. **Models テスト**: 全モデルの init / computed / Codable テスト
2. **SessionStorage テスト**: CRUD 全操作のファイル I/O テスト
3. **DepthProcessor キーフレーム選択テスト**: shouldCapture 判定ロジック
4. **ARSessionManager.relativeTransform テスト**: 相対姿勢計算

### 実装に必要な変更

1. **Linux 用 simd 互換層**: `simd_quatf`, `simd_float4x4`, `simd_length()` 等のシム
2. **条件付きコンパイル**: `#if canImport(ARKit)` 等でプラットフォーム分岐
3. **Swift Package Manager 基盤**: `Package.swift` でテストターゲット定義

### 実機テストが必要なもの（スコープ外）

- CVPixelBuffer 処理（depthToBinary, confidenceToData, colorToJPEGData）
- ARKit セッション管理（startSession, delegate callbacks）
- SwiftUI ビューのレンダリング
- LiDAR センサーデータ取得

## 影響

- ソースファイルに `#if canImport()` の条件付きコンパイルが追加される
- `Package.swift` が追加され、`swift test` でテスト実行可能になる
- 既存の Xcode プロジェクトのビルドには影響しない
