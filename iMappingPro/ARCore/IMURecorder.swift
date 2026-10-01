#if os(iOS) && canImport(CoreMotion)
import CoreMotion
import Foundation

final class IMURecorder {

    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()
    private let lock = NSLock()
    private var samples: [IMUSample] = []
    private var generation = 0
    private var isRecording = false

    init() {
        operationQueue.name = "com.imappingpro.arcore.imu"
        operationQueue.maxConcurrentOperationCount = 1
    }

    func beginRecording() {
        lock.lock()
        isRecording = false
        generation &+= 1
        samples.removeAll(keepingCapacity: true)
        let currentGeneration = generation
        lock.unlock()

        stopUpdates()
        lock.lock()
        guard self.generation == currentGeneration else {
            lock.unlock()
            return
        }
        isRecording = true
        lock.unlock()
        startUpdates(generation: currentGeneration)
    }

    func resumeRecording() {
        lock.lock()
        guard !isRecording else {
            lock.unlock()
            return
        }
        isRecording = true
        let currentGeneration = generation
        lock.unlock()

        startUpdates(generation: currentGeneration)
    }

    func pauseRecording() {
        lock.lock()
        isRecording = false
        lock.unlock()
        stopUpdates()
    }

    func finishRecording() -> [IMUSample] {
        pauseRecording()
        lock.lock()
        let result = samples
        lock.unlock()
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    func resetRecording() {
        pauseRecording()
        lock.lock()
        generation &+= 1
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func startUpdates(generation: Int) {
        let updateInterval = 1.0 / 200.0
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = updateInterval
            motionManager.startAccelerometerUpdates(to: operationQueue) { [weak self] data, _ in
                guard let data else { return }
                let acceleration = data.acceleration
                self?.append(
                    IMUSample(
                        sensor: .accelerometer,
                        timestamp: data.timestamp,
                        x: acceleration.x,
                        y: acceleration.y,
                        z: acceleration.z
                    ),
                    generation: generation
                )
            }
        }
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = updateInterval
            motionManager.startGyroUpdates(to: operationQueue) { [weak self] data, _ in
                guard let data else { return }
                let rotationRate = data.rotationRate
                self?.append(
                    IMUSample(
                        sensor: .gyroscope,
                        timestamp: data.timestamp,
                        x: rotationRate.x,
                        y: rotationRate.y,
                        z: rotationRate.z
                    ),
                    generation: generation
                )
            }
        }
    }

    private func stopUpdates() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }

    private func append(_ sample: IMUSample, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording, self.generation == generation else { return }
        samples.append(sample)
    }
}
#endif
