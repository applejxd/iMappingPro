import XCTest
@testable import iMappingProCore

/// 姿勢不連続の破棄判定（A-3）と低品質フレームの不採用（B-6）
final class KeyframeMotionValidationTests: XCTestCase {

    private var processor: DepthProcessor!

    override func setUp() {
        super.setUp()
        processor = DepthProcessor()
    }

    // MARK: - isPlausibleMotion

    func testPlausibleMotionForNormalHandheldMovement() {
        // 33ms で 5cm・3° はごく普通の手持ち移動
        XCTAssertTrue(DepthProcessor.isPlausibleMotion(
            translationDelta: 0.05,
            rotationDelta: 0.05,
            timeDelta: 0.033
        ))
    }

    func testImplausibleTranslationJump() {
        // 実測された初期化異常: 33ms で 0.878m
        XCTAssertFalse(DepthProcessor.isPlausibleMotion(
            translationDelta: 0.878,
            rotationDelta: 0.0,
            timeDelta: 0.033
        ))
    }

    func testImplausibleRotationJump() {
        // 実測された初期化異常: 16.7ms で 161.6° (≈2.82 rad)
        XCTAssertFalse(DepthProcessor.isPlausibleMotion(
            translationDelta: 0.0,
            rotationDelta: 2.82,
            timeDelta: 0.0167
        ))
    }

    func testNonPositiveTimeDeltaIsImplausible() {
        XCTAssertFalse(DepthProcessor.isPlausibleMotion(
            translationDelta: 0.0,
            rotationDelta: 0.0,
            timeDelta: 0
        ))
        XCTAssertFalse(DepthProcessor.isPlausibleMotion(
            translationDelta: 0.0,
            rotationDelta: 0.0,
            timeDelta: -0.01
        ))
    }

    func testLargeMovementOverLongIntervalIsPlausible() {
        // 1 秒で 1m は歩行速度の範囲
        XCTAssertTrue(DepthProcessor.isPlausibleMotion(
            translationDelta: 1.0,
            rotationDelta: 1.0,
            timeDelta: 1.0
        ))
    }

    // MARK: - evaluate

    func testEvaluateFirstFrameRequiresReliableTracking() {
        XCTAssertEqual(
            processor.evaluate(
                translation: .zero,
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0,
                isFirst: true,
                tracking: .normal
            ),
            .capture
        )

        XCTAssertEqual(
            processor.evaluate(
                translation: .zero,
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0,
                isFirst: true,
                tracking: .limitedInitializing
            ),
            .skip,
            "初期化中のフレームは原点にしない"
        )
    }

    func testEvaluateSkipsExcessiveMotion() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // 閾値を超える移動だがモーションブラーが強いので採用しない
        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.1, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0.1,
                isFirst: false,
                tracking: .limitedExcessiveMotion
            ),
            .skip
        )
    }

    func testEvaluateDetectsDiscontinuity() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // 33ms で 0.878m の飛び
        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.878, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0.033,
                isFirst: false,
                tracking: .normal
            ),
            .discontinuity
        )
    }

    /// 見送ったフレームも不連続判定の基準になる（キーフレーム間隔で判定すると
    /// 時間差が伸びて飛びを見逃す）
    func testEvaluateUsesPreviousFrameNotLastKeyframeForDiscontinuity() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        // 閾値未満の微小移動を 0.5 秒ぶん見送る
        for step in 1...30 {
            let time = TimeInterval(step) * 0.0167
            XCTAssertEqual(
                processor.evaluate(
                    translation: SIMD3<Float>(0.001 * Float(step), 0, 0),
                    quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                    timestamp: time,
                    isFirst: false,
                    tracking: .normal
                ),
                .skip
            )
        }

        // 直前フレームから 16.7ms で 0.878m の飛び
        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.908, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 30 * 0.0167 + 0.0167,
                isFirst: false,
                tracking: .normal
            ),
            .discontinuity
        )
    }

    /// 配送順の乱れで時刻が逆行したフレームは、不連続ではなく見送りにする
    ///
    /// メインスレッドが詰まると ARKit は時刻の巻き戻ったフレームを配送することがある。
    /// これを不連続と誤判定するとキャプチャが停止してしまう（実機ログ:
    /// `dt: -0.066671s, dpos: 0.009579m, drot: 0.039542rad` で停止）。
    func testEvaluateSkipsOutOfOrderFrameInsteadOfDiscontinuity() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 1.0
        )

        // 時刻が 66ms 巻き戻り、移動量は正常な範囲
        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.009579, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 1.0 - 0.066671,
                isFirst: false,
                tracking: .normal
            ),
            .skip
        )

        // 逆行フレームで基準が巻き戻っていないので、後続の正常フレームは通常判定される
        // （16.7ms で 6cm = 3.6m/s。速度上限 5m/s 内かつキーフレーム閾値 5cm 以上）
        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.06, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 1.0167,
                isFirst: false,
                tracking: .normal
            ),
            .capture
        )
    }

    /// 同一時刻の重複配送も不連続にしない
    func testEvaluateSkipsDuplicateTimestampFrame() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 1.0
        )

        XCTAssertEqual(
            processor.evaluate(
                translation: .zero,
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 1.0,
                isFirst: false,
                tracking: .normal
            ),
            .skip
        )
    }

    func testEvaluateCapturesNormalKeyframe() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.06, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0.1,
                isFirst: false,
                tracking: .normal
            ),
            .capture
        )
    }

    func testEvaluateSkipsBelowThreshold() {
        processor.updateLast(
            translation: .zero,
            quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            timestamp: 0
        )

        XCTAssertEqual(
            processor.evaluate(
                translation: SIMD3<Float>(0.01, 0, 0),
                quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                timestamp: 0.1,
                isFirst: false,
                tracking: .normal
            ),
            .skip
        )
    }
}
