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
