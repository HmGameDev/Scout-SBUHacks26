import CoreMotion

/// Watches the gyroscope. Depth frames captured during a violent jolt are blurry,
/// so they're skipped. (ARKit also fuses the gyro into the camera pose it reports.)
final class MotionMonitor {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var latestRate: Double = 0

    /// Safe to read from any thread.
    var isMovingTooFast: Bool {
        lock.withLock { latestRate } > Tuning.maxRotationRate
    }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let r = motion?.rotationRate else { return }
            let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            self.lock.withLock { self.latestRate = rate }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lock.withLock { latestRate = 0 }
    }
}
