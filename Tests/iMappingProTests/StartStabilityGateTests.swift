import XCTest
@testable import iMappingProCore

/// 原点確定前の姿勢安定判定
final class StartStabilityGateTests: XCTestCase {

    private let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// 60fps 相当で微小移動しながら評価する
    private func feed(
        _ gate: inout StartStabilityGate,
        frames: Int,
        startTime: TimeInterval = 0,
        step: TimeInterval = 0.0167
    ) -> Bool {
        var accepted = false
        for index in 0..<frames {
            accepted = gate.evaluate(
                translation: SIMD3<Float>(0.001 * Float(index), 0, 0),
                quaternion: identity,
                timestamp: startTime + Double(index) * step
            )
        }
        return accepted
    }

    func testFirstFrameIsNotAcceptedImmediately() {
        var gate = StartStabilityGate()
        XCTAssertFalse(gate.evaluate(translation: .zero, quaternion: identity, timestamp: 0))
    }

    func testRejectsUntilRequiredDurationElapsed() {
        var gate = StartStabilityGate()
        // 0.4 秒ぶん（必要な 0.5 秒未満）
        XCTAssertFalse(feed(&gate, frames: 24))
    }

    func testAcceptsAfterContinuousStablePeriod() {
        var gate = StartStabilityGate()
        // 0.5 秒を超えるまで連続入力すれば原点として採用できる
        XCTAssertTrue(feed(&gate, frames: 40))
    }

    func testJumpRestartsStabilityWindow() {
        var gate = StartStabilityGate()
        XCTAssertTrue(feed(&gate, frames: 40))

        var jumped = StartStabilityGate()
        _ = feed(&jumped, frames: 29)
        // 16.7ms で 0.9m の飛び（ARKit の初期化異常相当）
        XCTAssertFalse(jumped.evaluate(
            translation: SIMD3<Float>(0.9, 0, 0),
            quaternion: identity,
            timestamp: 29 * 0.0167
        ))
        XCTAssertEqual(jumped.lastRejectedDelta?.translation ?? 0, 0.872, accuracy: 0.01)

        // 飛んだ直後は計測がやり直しになるため、すぐには採用されない
        XCTAssertFalse(jumped.evaluate(
            translation: SIMD3<Float>(0.9, 0, 0),
            quaternion: identity,
            timestamp: 30 * 0.0167
        ))
        XCTAssertNil(jumped.lastRejectedDelta, "診断値はフレームごとに更新される")
    }

    func testResetClearsState() {
        var gate = StartStabilityGate()
        _ = feed(&gate, frames: 40)
        gate.reset()
        XCTAssertNil(gate.lastRejectedDelta)
        XCTAssertFalse(gate.evaluate(translation: .zero, quaternion: identity, timestamp: 10))
    }

    func testRotationAngleMatchesQuaternionDifference() {
        // Z 軸まわり 90°: (0, 0, sin45°, cos45°)
        let half = (Float.pi / 4)
        let rotated = simd_quatf(ix: 0, iy: 0, iz: sin(half), r: cos(half))
        XCTAssertEqual(
            DepthProcessor.rotationAngle(between: identity, and: rotated),
            .pi / 2,
            accuracy: 0.001
        )
    }
}
