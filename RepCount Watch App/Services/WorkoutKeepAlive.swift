import Foundation
import HealthKit

/// Keeps the app running while the wrist is down.
///
/// Without this, watchOS suspends the app the moment the wrist drops and CoreMotion
/// stops delivering — which is most of a set. A workout session alone is not enough:
/// it has to be an *actively collecting* one, so an `HKLiveWorkoutBuilder` is started
/// and `beginCollection` is called. A session whose collection never began does not
/// hold CoreMotion open, and the recording comes back with half its samples gone.
@MainActor
final class WorkoutKeepAlive: NSObject, ObservableObject {
    @Published private(set) var state: HKWorkoutSessionState = .notStarted
    @Published private(set) var isCollecting = false
    @Published private(set) var lastFailure: String?

    /// True only when the session is running AND collection has actually begun.
    /// Anything less does not keep motion alive.
    var isHolding: Bool { state == .running && isCollecting }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastFailure = "HealthKit unavailable"
            return false
        }
        let types: Set = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: types, read: types)
            return true
        } catch {
            lastFailure = "authorization: \(error.localizedDescription)"
            return false
        }
    }

    func start() async {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            session = s
            builder = b
            s.startActivity(with: Date())
            try await b.beginCollection(at: Date())
            isCollecting = true
        } catch {
            lastFailure = "start: \(error.localizedDescription)"
            isCollecting = false
        }
    }

    func stop() async {
        guard let s = session else { return }
        s.end()
        if let b = builder, isCollecting {
            try? await b.endCollection(at: Date())
            _ = try? await b.finishWorkout()
        }
        isCollecting = false
        session = nil
        builder = nil
    }
}

extension WorkoutKeepAlive: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in self.state = toState }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            self.lastFailure = "session: \(error.localizedDescription)"
            self.isCollecting = false
        }
    }
}
