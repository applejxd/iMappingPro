import XCTest
@testable import iMappingProCore

final class DepthProcessorKeyframeTests: XCTestCase {

    private var processor: DepthProcessor!

    override func setUp() {
        super.setUp()
        processor = DepthProcessor()
    }

    // MARK: - First Frame

    func testShouldCaptureFirstFrame() {
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0,
            isFirst: true
        )
        XCTAssertTrue(result, "初回フレームは常にキャプチャすべき")
    }

    // MARK: - Time-based

    func testShouldCaptureAfterMaxInterval() {
        // 最初のフレームの状態を設定
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // maxFrameInterval (1.0秒) を超えたタイムスタンプ
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0, 0, 0), // 移動なし
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), // 回転なし
            timestamp: 1.0,
            isFirst: false
        )
        XCTAssertTrue(result, "1秒経過後はキャプチャすべき")
    }

    func testShouldNotCaptureBeforeMaxInterval() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.5,
            isFirst: false
        )
        XCTAssertFalse(result, "閾値未満ではキャプチャしない")
    }

    // MARK: - Translation-based

    func testShouldCaptureWithTranslation() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // minTranslationDistance (0.05m = 5cm) を超える移動
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0.06, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertTrue(result, "5cm以上の移動でキャプチャすべき")
    }

    func testShouldNotCaptureWithSmallTranslation() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // minTranslationDistance 未満の移動
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0.02, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertFalse(result, "5cm未満の移動ではキャプチャしない")
    }

    func testShouldCaptureWith3DTranslation() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // 3軸での移動 (各軸0.03 → 距離 ≈ 0.052 > 0.05)
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0.03, 0.03, 0.03),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertTrue(result, "3D距離が閾値を超えればキャプチャすべき")
    }

    // MARK: - Rotation-based

    func testShouldCaptureWithRotation() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // minRotationAngle (0.05 rad ≈ 2.87°) を超える回転
        // 5° の回転 ≈ 0.0436 rad の半角 → sin(2.5°) ≈ 0.0436
        let angle: Float = 0.1 // ~5.7°
        let halfAngle = angle / 2
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(
                ix: 0,
                iy: sin(halfAngle),
                iz: 0,
                r: cos(halfAngle)
            ),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertTrue(result, "回転閾値を超えればキャプチャすべき")
    }

    // MARK: - UpdateLast

    func testUpdateLast() {
        let t = SIMD3<Float>(1, 2, 3)
        // 正規化されたクォータニオンを使用
        let q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        processor.updateLast(translation: t, quaternion: q, timestamp: 5.0)

        // 同じ位置・回転・直近のタイムスタンプ → キャプチャしない
        let result = processor.shouldCapture(
            translation: t,
            quaternion: q,
            timestamp: 5.1,
            isFirst: false
        )
        XCTAssertFalse(result, "updateLast で更新された状態からの小さな変化ではキャプチャしない")
    }

    // MARK: - Reset

    func testReset() {
        // 状態を更新
        processor.updateLast(
            translation: SIMD3<Float>(10, 10, 10),
            quaternion: simd_quatf(ix: 0.5, iy: 0.5, iz: 0, r: 0.5),
            timestamp: 100
        )

        processor.reset()

        // リセット後は原点からの比較になる
        // 小さい移動でもキャプチャされないことを確認（原点近く）
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0.01, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertFalse(result, "リセット後は原点状態に戻る")
    }

    // MARK: - Threshold Values

    func testThresholdValues() {
        XCTAssertEqual(processor.minTranslationDistance, 0.05, "移動閾値は5cm")
        XCTAssertEqual(processor.minRotationAngle, 0.05, "回転閾値は0.05rad")
        XCTAssertEqual(processor.maxFrameInterval, 1.0, "最大フレーム間隔は1秒")
    }

    // MARK: - Edge Cases

    func testExactlyAtTranslationThreshold() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // ちょうど閾値の移動
        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0.05, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0.1,
            isFirst: false
        )
        XCTAssertTrue(result, "閾値ちょうどはキャプチャする (>=)")
    }

    func testExactlyAtTimeThreshold() {
        processor.updateLast(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        let result = processor.shouldCapture(
            translation: SIMD3<Float>(0, 0, 0),
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 1.0,
            isFirst: false
        )
        XCTAssertTrue(result, "時間閾値ちょうどはキャプチャする (>=)")
    }
}
