import Foundation
import CoreMotion

/// Records one contiguous set of device motion.
///
/// Reference frame is `.xMagneticNorthZVertical`: Z is locked to vertical by gravity
/// and X to magnetic north by the magnetometer, so yaw is an absolute heading rather
/// than drifting from wherever the watch happened to start.
@MainActor
final class CaptureManager: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var quality: CaptureQuality?
    @Published private(set) var lastFailure: String?

    let keepAlive = WorkoutKeepAlive()
    private let activity = ActivityMonitor()

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    // Written by the motion queue, read by the counting pass, neither on the main
    // actor. `lock` is what makes that safe, so the isolation is opted out of
    // explicitly rather than by accident.
    nonisolated(unsafe) private var samples: [MotionSample] = []
    private let lock = NSLock()
    private var ticker: Timer?
    private var startedAt: Date?

    /// 100 Hz, the rate the reference recordings were made at.
    private let interval = 0.01

    init() {
        queue.name = "com.jaredgantt.workset.motion"
        queue.maxConcurrentOperationCount = 1
    }

    func start() async {
        guard !isRecording else { return }
        guard motion.isDeviceMotionAvailable else {
            lastFailure = "device motion unavailable"
            return
        }
        guard await keepAlive.requestAuthorization() else { return }
        await keepAlive.start()

        lock.withLock { samples.removeAll() }
        sampleCount = 0
        quality = nil
        lastFailure = nil
        startedAt = Date()

        activity.start()
        motion.deviceMotionUpdateInterval = interval
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: queue) { [weak self] data, error in
            guard let self, let d = data else { return }
            let act = self.activity.snapshot()
            let s = MotionSample(
                sensorTime: d.timestamp,
                userAccel: SIMD3(d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z),
                rotationRate: SIMD3(d.rotationRate.x, d.rotationRate.y, d.rotationRate.z),
                gravity: SIMD3(d.gravity.x, d.gravity.y, d.gravity.z),
                attitude: SIMD3(d.attitude.pitch, d.attitude.roll, d.attitude.yaw),
                magAccuracy: Int(d.magneticField.accuracy.rawValue),
                activityMask: act.mask,
                activityConfidence: act.confidence)
            self.lock.withLock { self.samples.append(s) }
        }

        isRecording = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() async -> [MotionSample] {
        guard isRecording else { return [] }
        motion.stopDeviceMotionUpdates()
        activity.stop()
        ticker?.invalidate(); ticker = nil
        await keepAlive.stop()
        isRecording = false

        let out = lock.withLock { samples }
        quality = CaptureQuality.measure(out)
        sampleCount = out.count
        return out
    }

    /// Everything recorded so far. Safe to call from any thread — the counting pass
    /// runs off the main actor and needs its own copy, because the motion queue is
    /// still appending while it works.
    nonisolated func snapshot() -> [MotionSample] {
        return lock.withLock { samples }
    }

    /// Remove and return everything accumulated since the last call.
    ///
    /// Always-on counting runs for a whole workout, so nothing can accumulate here
    /// indefinitely — an hour at 100 Hz is 360,000 samples. The session keeps only
    /// the window it needs and drops the rest, so retention is its decision rather
    /// than a side effect of recording.
    nonisolated func drain() -> [MotionSample] {
        lock.withLock {
            let out = samples
            samples.removeAll(keepingCapacity: true)
            return out
        }
    }

    private func tick() {
        let n = lock.withLock { samples.count }
        sampleCount = n
        if let s = startedAt { elapsed = Date().timeIntervalSince(s) }
    }
}
