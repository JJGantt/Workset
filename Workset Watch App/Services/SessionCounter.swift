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

    private let feedback = Feedback()
    private var machine = SessionMachine()
    private var running = false
    private var pass: Task<Void, Never>?

    /// Floor between passes. Not a cadence — the next pass starts as soon as the
    /// last one finishes, and this only stops a fast watch from spinning.
    ///
    /// A fixed 0.5s timer was worse than it looked: a tick that arrived while a pass
    /// was still running was DROPPED, so on hardware where a pass takes longer than
    /// the tick the real cadence silently doubled and every rep was announced late.
    /// Self-pacing cannot drift that way — it is always running as fast as the
    /// hardware allows, and `lastPassMs` says what that actually costs.
    private let floorInterval: TimeInterval = 0.2
    private var pull: () -> [MotionSample] = { [] }

    func begin(pull: @escaping () -> [MotionSample]) {
        self.pull = pull
        machine = SessionMachine()
        count = 0
        sets = []
        phase = .armed
        running = true
        tick()
    }

    func end() {
        running = false
        pass?.cancel(); pass = nil
        if case .closed(let rec, let samples)? = machine.finish() {
            CaptureUploader.upload(samples, verdict: rec)
            sets = machine.sets
            feedback.setEnded()
        }
        feedback.release()
        phase = .off
        count = 0
    }

    private func tick() {
        guard running, pass == nil else { return }
        let started = Date()
        let new = pull()
        var m = machine
        pass = Task.detached(priority: .userInitiated) {
            let started = Date()
            let events = m.ingest(new)
            let ms = Date().timeIntervalSince(started) * 1000
            let snapshot = m
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(snapshot, events: events, ms: ms)
                self.pass = nil
                guard self.running else { return }
                let elapsed = Date().timeIntervalSince(started)
                let wait = max(0, self.floorInterval - elapsed)
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.tick()
                }
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
                // Lands at three reps and announces all three at once, so it has to
                // be clearly distinct from a single rep tick.
                feedback.locked()
            case .reps(let n):
                feedback.rep(n)
            case .closed(let rec, let samples):
                // The log carries the conservative count, which can be one below
                // what was announced. The record is the authority, not the haptics.
                count = rec.count
                // Save the recording AND what this version of the algorithm decided
                // about it — count, rep boundaries, gate values. A wrong number is
                // only useful if the data behind it survives, and an improvement is
                // only visible if the previous verdict was written down.
                CaptureUploader.upload(samples, verdict: rec)
                feedback.setEnded()
            }
        }
    }
}
