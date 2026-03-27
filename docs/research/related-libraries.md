# 関連ライブラリ・フレームワーク調査

## Apple 公式フレームワーク

### ARKit
- **役割**: AR セッション管理、6DOF 追跡、LiDAR 深度取得、メッシュ再構成
- **バージョン**: iOS 11+ (LiDAR: iOS 13.4+)
- **依存**: なし (システムフレームワーク)
- **ドキュメント**: https://developer.apple.com/documentation/arkit

### RealityKit
- **役割**: ARKit 上の高レベル 3D レンダリングエンジン
- **バージョン**: iOS 13+
- **LiDAR 連携**: `ARView` が LiDAR メッシュ可視化をネイティブサポート
- **特徴**:
  - `ARView.debugOptions = [.showSceneUnderstanding]` でメッシュ表示
  - Entity-Component システム
  - PBR マテリアル対応

### SceneKit
- **役割**: 3D シーン管理・レンダリング
- **バージョン**: iOS 8+
- **ARKit 連携**: `ARSCNView` 経由
- **特徴**: 成熟した API、Metal バックエンド

### Metal
- **役割**: GPU コンピュート・グラフィクス
- **用途**: 深度マップの GPU 処理、カスタムシェーダ
- **深度処理例**:
  ```swift
  // MTLTexture として深度マップを処理
  let textureDescriptor = MTLTextureDescriptor()
  textureDescriptor.pixelFormat = .r32Float
  textureDescriptor.width = depthWidth
  textureDescriptor.height = depthHeight
  ```

### AVFoundation
- **役割**: カメラ制御、ビデオ録画
- **ARKit との関係**: ARKit が内部で AVFoundation を使用
- **注意**: ARKit セッション中は AVCaptureSession と競合するため、RGB 取得は ARFrame 経由で行う

### CoreData
- **役割**: セッションメタデータの永続化
- **代替**: `Codable` + JSON + FileManager でも十分（セッション数が少ない場合）

### SwiftUI
- **役割**: UI 実装
- **ARKit 連携**: `UIViewRepresentable` / `UIViewControllerRepresentable` でラップ
- **バージョン**: iOS 14+ 推奨 (iOS 13 は機能制限あり)

## サードパーティライブラリ

### Open3D (Python / C++)
- **用途**: ポイントクラウド処理・可視化（デスクトップ側での後処理用）
- **iOS 対応**: なし（サーバ/PC サイドのツール）
- **ライセンス**: MIT
- **URL**: https://www.open3d.org/

### PCL (Point Cloud Library)
- **用途**: ポイントクラウド処理
- **iOS 対応**: 限定的（クロスコンパイルは困難）
- **ライセンス**: BSD

### ROS2 (Robot Operating System)
- **用途**: ロボティクス向けミドルウェア（研究・開発環境）
- **iOS 対応**: なし
- **関連**: iOS アプリ → ROS2 への出力フォーマット互換性を考慮する場合あり

## iOS 向け 3D スキャンアプリの実装パターン

### パターン 1: RealityKit ARView + LiDAR
```swift
import RealityKit
import ARKit

class ScanViewController: UIViewController {
    var arView: ARView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = .sceneDepth
        arView.session.run(config)
        arView.debugOptions = [.showSceneUnderstanding]
    }
}
```

### パターン 2: ARSCNView (SceneKit)
```swift
import ARKit
import SceneKit

class ScanViewController: UIViewController, ARSCNViewDelegate {
    var sceneView: ARSCNView!
    // メッシュを SCNGeometry に変換して表示
}
```

### パターン 3: カスタム Metal レンダラ
- 最高のパフォーマンスと柔軟性
- 実装コスト高
- 深度マップの GPU 上での直接処理が可能

## データ形式比較

| 形式 | 用途 | サイズ | 精度 | ツール対応 |
|---|---|---|---|---|
| JPEG | RGB 画像 | 小 | 非可逆 | 広範 |
| PNG | RGB / Confidence | 中 | 可逆 | 広範 |
| EXR | 深度マップ | 大 | Float32 | CG ツール |
| .bin (raw float) | 深度マップ | 中 | Float32 | カスタム |
| PLY | ポイントクラウド | 中〜大 | Float32 | Open3D, Meshlab |
| TUM RGB-D format | RGBD + 姿勢 | 標準 | Float32 | ORB-SLAM, 研究 |

### TUM RGB-D 形式
研究コミュニティで広く使われる形式:
```
# depth.txt
timestamp depth_filename
# rgb.txt  
timestamp rgb_filename
# groundtruth.txt
timestamp tx ty tz qx qy qz qw
```

## 推奨スタック (本プロジェクト)

| レイヤー | 採用技術 | 理由 |
|---|---|---|
| AR セッション | ARKit | 公式、LiDAR 対応、高精度 VIO |
| UI | SwiftUI | モダン、宣言的 |
| 3D プレビュー | RealityKit (ARView) | LiDAR メッシュ表示のネイティブサポート |
| 深度処理 | ARKit (CVPixelBuffer) | 追加ライブラリ不要 |
| 永続化 | FileManager + JSON (Codable) | シンプル、外部依存なし |
| 画像保存 | UIImage + JPEG / CVPixelBuffer → Data | 標準 API |
