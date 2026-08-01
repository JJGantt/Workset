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
    /// A closed set plus the id of the report that logged it, so the wrist can
    /// still correct or remove it afterwards.
    struct Logged: Identifiable {
        let id = UUID()
        let set: CountedSet
        var reportID: Int?
        var adjust = 0          // what the +/- buttons have applied
        var removed = false
        var reps: Int { max(1, set.count + adjust) }
    }

    @Published private(set) var sets: [Logged] = []
    /// What the set watcher is armed to, or nil when nothing is being logged.
    @Published private(set) var armedAs: String?
    /// The last check could not reach the server at all. Distinct from "nothing is
    /// armed": one means arm it, the other means the watch is offline.
    @Published private(set) var watcherUnreachable = false
    /// The armed exercise and weight as separate values, so a capture records what it
    /// IS rather than only how it is displayed. This is what makes a per-exercise
    /// shape library possible: a recording says which movement it is, on its own.
    private var armedExercise: String?
    private var armedWeight: Double?
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
    /// The watcher can be set, changed or allowed to expire while the app is running,
    /// so the badge is re-checked rather than read once.
    private var lastArmedCheck = Date.distantPast

    func begin(pull: @escaping () -> [MotionSample]) {
        self.pull = pull
        machine = SessionMachine()
        count = 0
        sets = []
        phase = .armed
        // Ask straight away what the rep watcher is set to. Knowing whether sets are
        // being logged is only useful BEFORE lifting; discovering it afterwards is
        // no use at all.
        refreshArmed()
        running = true
        tick()
    }

    func end() {
        running = false
        pass?.cancel(); pass = nil
        switch machine.finish() {
        case .closed(let rec, let samples)?:
            // A set ended by pressing Stop is still a set: it uploads AND logs, the
            // same as one that closed on its own. This previously only uploaded, so
            // the last set of a workout never reached the training log.
            CaptureUploader.upload(samples, verdict: rec,
                                   exercise: armedExercise, weightLbs: armedWeight)
            logClosed(rec)
            feedback.setEnded()
        case .tooShort(let rec, let samples)?:
            // Too few reps to be a set. The recording is still kept — losing it here
            // would throw away the only labelled evidence of a false detection.
            CaptureUploader.upload(samples, verdict: rec, exercise: armedExercise,
                                   weightLbs: armedWeight, cancelled: true)
        default:
            break
        }
        feedback.release()
        phase = .off
        count = 0
    }

    private func tick() {
        guard running else { return }
        if Date().timeIntervalSince(lastArmedCheck) > 15 {
            lastArmedCheck = Date()
            refreshArmed()
        }
        guard pass == nil else { return }
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

    /// Record the set locally and report it, so it lands in the training log.
    private func logClosed(_ rec: CountedSet) {
        sets.append(Logged(set: rec, reportID: nil))
        let idx = sets.count - 1
        SetReporter.report(reps: rec.count, at: Date(),
                           session: "watch", algorithm: rec.algorithm) { [weak self] id in
            Task { @MainActor in
                guard let self, idx < self.sets.count else { return }
                self.sets[idx].reportID = id
            }
        }
        refreshArmed()
    }

    /// Throw away the set being counted right now, without stopping the session.
    ///
    /// The alternative was switching the whole session off and on again, which clears
    /// the list of sets already done — losing a workout's worth of history to reject
    /// one bad set.
    ///
    /// The recording is still uploaded, marked cancelled. A set the counter recognised
    /// and the lifter rejected is a labelled false positive, and there is no other way
    /// to produce one; discarding it would throw away the only recording that proves
    /// the counter fires on something that is not a set.
    func cancelCurrent() {
        let samples = machine.discard()
        count = 0
        phase = .armed
        CaptureUploader.upload(samples, verdict: nil, exercise: armedExercise,
                               weightLbs: armedWeight, cancelled: true)
        feedback.setEnded()
    }

    /// Add a set by hand, at whatever the watcher is armed to.
    ///
    /// For everything the wrist cannot see — leg press, seated calf raise, anything
    /// where the arm holds still. It goes through the identical path a counted set
    /// takes, so it lands in the training log the same way and can be corrected or
    /// removed from the wrist afterwards.
    func addManual(reps: Int) {
        guard reps > 0 else { return }
        let rec = CountedSet(count: reps, startedAt: 0, endedAt: 0,
                             seedSpread: 0, travelCm: 0, repEnds: [], repFired: [],
                             algorithm: "manual")
        logClosed(rec)
    }

    /// The rep count of the last set that was not removed, or nil if there is none.
    /// What "repeat" repeats.
    var lastReps: Int? { sets.last(where: { !$0.removed })?.reps }

    /// The +/- buttons: fix a count on the wrist.
    func adjust(_ index: Int, by delta: Int) {
        guard sets.indices.contains(index), !sets[index].removed else { return }
        let next = max(1, sets[index].set.count + sets[index].adjust + delta)
        sets[index].adjust = next - sets[index].set.count
        if let id = sets[index].reportID { SetReporter.correct(reportID: id, reps: next) }
    }

    /// The X button: this was not a set.
    func remove(_ index: Int) {
        guard sets.indices.contains(index) else { return }
        sets[index].removed = true
        if let id = sets[index].reportID { SetReporter.remove(reportID: id) }
    }

    func refreshArmed() {
        lastArmedCheck = Date()
        SetReporter.armedExercise { [weak self] info, reachable in
            Task { @MainActor in
                self?.watcherUnreachable = !reachable
                // A failed check leaves the last known arming in place rather than
                // blanking it. Dropping to "not logging" because one request timed out
                // says the sets are not being recorded when they are.
                guard reachable else { return }
                self?.armedAs = info?.label
                self?.armedExercise = info?.exercise
                self?.armedWeight = info?.weight
            }
        }
    }

    private func apply(_ m: SessionMachine, events: [SessionMachine.Event], ms: Double) {
        machine = m
        lastPassMs = ms
        count = m.count
        // `sets` is owned here, not mirrored from the machine: it carries the report
        // ids and the wrist edits, which the machine knows nothing about.
        phase = m.phase == .counting ? .counting : .armed
        for e in events {
            switch e {
            case .committed:
                // Lands at three reps and announces all three at once, so it has to
                // be clearly distinct from a single rep tick.
                feedback.locked()
            case .reps(let n):
                feedback.rep(n)
            case .tooShort(let rec, let samples):
                // Not a set: nothing logged, nothing announced, no entry on the wrist.
                // The recording is still kept, marked cancelled, because a detection
                // the threshold rejected is a labelled false positive and there is no
                // other way to produce one.
                count = 0
                CaptureUploader.upload(samples, verdict: rec, exercise: armedExercise,
                                       weightLbs: armedWeight, cancelled: true)
                feedback.release()
            case .closed(let rec, let samples):
                // The log carries the conservative count, which can be one below
                // what was announced. The record is the authority, not the haptics.
                count = rec.count
                logClosed(rec)
                // Save the recording AND what this version of the algorithm decided
                // about it — count, rep boundaries, gate values. A wrong number is
                // only useful if the data behind it survives, and an improvement is
                // only visible if the previous verdict was written down.
                CaptureUploader.upload(samples, verdict: rec,
                                       exercise: armedExercise, weightLbs: armedWeight)
                feedback.setEnded()
            }
        }
    }
}
