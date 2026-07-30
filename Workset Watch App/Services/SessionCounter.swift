import Foundation
import WatchKit

/// Drives `SessionMachine` on the watch: timers, threading, haptics, published state.
///
/// All the decisions — is this a set, has it ended, what is the count — live in
/// `SessionMachine`, which is platform-free and driven over recorded streams by the
/// offline verifier. This class deliberately holds none of them, so what ships is
/// the logic that was tested rather than a second copy of it.
@MainActor
final class SessionCounter: ObservableObject {

    enum Phase { case off, armed, counting }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var count = 0
    @Published private(set) var sets: [CountedSet] = []
    /// Cost of the last counting pass. On screen because the update rate has to be
    /// judged against real hardware rather than assumed.
    @Published private(set) var lastPassMs: Double = 0

    private var machine = SessionMachine()
    private var timer: Timer?
    private var pass: Task<Void, Never>?
    private var pull: () -> [MotionSample] = { [] }

    func begin(pull: @escaping () -> [MotionSample]) {
        self.pull = pull
        machine = SessionMachine()
        count = 0
        sets = []
        phase = .armed
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func end() {
        timer?.invalidate(); timer = nil
        pass?.cancel(); pass = nil
        if case .closed(let rec, let samples)? = machine.finish() {
            CaptureUploader.upload(samples, verdict: rec)
            sets = machine.sets
            WKInterfaceDevice.current().play(.stop)
        }
        phase = .off
        count = 0
    }

    private func tick() {
        // One pass at a time. If the watch is slower than the tick, passes are
        // skipped rather than queued — a backlog would report older and older counts
        // while burning the battery that produced them.
        guard pass == nil else { return }
        let new = pull()
        var m = machine
        pass = Task.detached(priority: .userInitiated) {
            let started = Date()
            let events = m.ingest(new)
            let ms = Date().timeIntervalSince(started) * 1000
            let snapshot = m
            await MainActor.run { [weak self] in
                self?.apply(snapshot, events: events, ms: ms)
                self?.pass = nil
            }
        }
    }

    private func apply(_ m: SessionMachine, events: [SessionMachine.Event], ms: Double) {
        machine = m
        lastPassMs = ms
        count = m.count
        sets = m.sets
        phase = m.phase == .counting ? .counting : .armed
        for e in events {
            switch e {
            case .committed:
                // The first commit lands several reps at once. One
                // distinct haptic for "locked on", not a burst of clicks.
                WKInterfaceDevice.current().play(.notification)
            case .reps:
                WKInterfaceDevice.current().play(.click)
            case .closed(let rec, let samples):
                // Save the recording AND what this version of the algorithm decided
                // about it — count, rep boundaries, gate values. A wrong number is
                // only useful if the data behind it survives, and an improvement is
                // only visible if the previous verdict was written down.
                CaptureUploader.upload(samples, verdict: rec)
                WKInterfaceDevice.current().play(.stop)
            }
        }
    }
}
