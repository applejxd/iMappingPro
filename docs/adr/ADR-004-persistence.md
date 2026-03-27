# ADR-004: セッション永続化 — スキャンデータの保存・読み込み

**ステータス**: 完了  
**日付**: 2026-03-27  
**リリース対象**: v0.4 (永続化ビルド)

---

## コンテキスト

UI が完成した (v0.3) 状態を踏まえ、スキャンセッションのデータを
デバイスのストレージに永続化し、アプリ再起動後も参照できるようにする。

## 決定事項

### 1. ストレージ方針

**FileManager + JSON (Codable)** を採用。CoreData は避ける。

理由:
- セッション数は通常 100 件以下 → CoreData のオーバーヘッド不要
- バイナリファイル (深度マップ、画像) は CoreData に格納不向き
- ファイルシステム直接アクセスで外部ツールとの連携が容易

### 2. ディレクトリ構造

```
Documents/
└── iMappingPro/
    ├── sessions.json              # 全セッションのメタデータ一覧
    └── sessions/
        └── <session-uuid>/
            ├── metadata.json      # セッション詳細情報
            ├── poses.json         # 全フレームの6DOF姿勢
            └── frames/
                ├── 000000_color.jpg
                ├── 000000_depth.bin
                ├── 000000_conf.png
                ├── 000001_color.jpg
                ...
```

### 3. ファイル形式仕様

#### sessions.json
```json
{
  "version": 1,
  "sessions": [
    {
      "id": "uuid",
      "name": "リビング 2024-01-01",
      "created_at": "2024-01-01T10:00:00Z",
      "frame_count": 150,
      "duration_seconds": 30.5,
      "directory_name": "uuid"
    }
  ]
}
```

#### metadata.json
```json
{
  "id": "uuid",
  "name": "リビング 2024-01-01",
  "created_at": "2024-01-01T10:00:00Z",
  "frame_count": 150,
  "duration_seconds": 30.5,
  "device_model": "iPhone 15 Pro",
  "ios_version": "17.2"
}
```

#### poses.json
```json
{
  "session_id": "uuid",
  "frame_count": 150,
  "frames": [
    {
      "index": 0,
      "timestamp": 0.0,
      "translation": [0.0, 0.0, 0.0],
      "quaternion": [0.0, 0.0, 0.0, 1.0],
      "intrinsics": {"fx":1440.0,"fy":1440.0,"cx":960.0,"cy":720.0},
      "image_size": {"width":1920,"height":1440},
      "depth_size": {"width":256,"height":192}
    }
  ]
}
```

#### depth.bin フォーマット
```
Bytes 0-3:   width  (UInt32, little-endian)
Bytes 4-7:   height (UInt32, little-endian)
Bytes 8-...: float32 values, row-major order, unit: meters
Total size:  8 + width * height * 4 bytes
```

### 4. SessionStorage API

```swift
class SessionStorage {
    // セッション一覧
    func loadAllSessions() throws -> [ScanSession]
    func saveSessionList(_ sessions: [ScanSession]) throws
    
    // セッション作成・更新
    func createSessionDirectory(id: UUID) throws -> URL
    func saveMetadata(_ session: ScanSession) throws
    func savePoses(_ frames: [PoseFrame], sessionID: UUID) throws
    
    // フレームデータ保存
    func saveColorImage(_ pixelBuffer: CVPixelBuffer, index: Int, sessionID: UUID) throws
    func saveDepthMap(_ pixelBuffer: CVPixelBuffer, index: Int, sessionID: UUID) throws
    func saveConfidenceMap(_ pixelBuffer: CVPixelBuffer, index: Int, sessionID: UUID) throws
    
    // セッション削除
    func deleteSession(id: UUID) throws
    
    // セッションリネーム
    func renameSession(id: UUID, newName: String) throws
    
    // セッションの URL を取得
    func sessionDirectoryURL(id: UUID) -> URL
}
```

### 5. 保存フロー

```
[ScanViewModel.saveSession(name:)] 
  → 1. セッションディレクトリ作成
  → 2. 取得済みフレームバッファを captureQueue で非同期書き込み
       ├─ 2a. JPEG 書き込み (color)
       ├─ 2b. Float32 バイナリ書き込み (depth)
       └─ 2c. PNG 書き込み (confidence)
  → 3. poses.json 書き込み
  → 4. metadata.json 書き込み
  → 5. sessions.json 更新
  → 6. Main thread: 保存完了通知 → HistoryView へ遷移
```

### 6. エラーハンドリング

```swift
enum StorageError: LocalizedError {
    case directoryCreationFailed(URL)
    case encodingFailed(String)
    case decodingFailed(String)
    case fileNotFound(URL)
    case insufficientStorage
}
```

保存中のエラーは `ScanViewModel.errorMessage` にセットし、アラートで表示。

### 7. ストレージ容量見積もり

| 項目 | サイズ/フレーム | 150フレーム |
|---|---|---|
| JPEG (1920×1440, Q90) | ~500KB | ~75MB |
| Depth bin (256×192) | ~200KB | ~30MB |
| Confidence PNG | ~25KB | ~3.75MB |
| poses.json | ~500B | ~75KB |
| **合計** | **~725KB** | **~109MB** |

→ 30秒スキャン (150フレーム) で約 100MB。  
→ iPhone Pro の空き容量確認を保存前に実施する。

## 結果

### 実装内容 (v0.4)

- [x] `SessionStorage`: ファイル永続化クラス全メソッド
- [x] `ScanSession` / `PoseFrame`: Codable 対応確認
- [x] `DepthProcessor.saveDepthBinary()`: Float32 バイナリ保存
- [x] `ScanViewModel.saveSession()`: 保存フロー完全実装
- [x] エラーアラート表示
- [x] 保存中のプログレスインジケータ

### 検証基準

1. Save 後に Documents/iMappingPro/sessions/ 配下にディレクトリが生成される
2. poses.json が有効な JSON で正しいフレーム数を含む
3. アプリ再起動後に保存済みセッションが復元される
4. 複数セッションを保存・削除しても sessions.json が正しく更新される

## トレードオフ

- 非同期書き込み: UI がブロックされないが、バックグラウンドでのエラー処理が複雑
- JPEG 圧縮: 深度の精度は保持、RGB のみ非可逆 (研究用途では PNG を検討)
