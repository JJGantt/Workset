import Foundation
import AVFoundation
import WatchKit

/// What the wrist and the ear get told, and nothing else.
///
/// Counting is useless if you have to look at the watch to know it counted. The
/// point of the feedback is that a set can be done with your eyes anywhere else.
///
/// Haptic and sound fire together deliberately. On Apple Watch a haptic already
/// carries its own audio cue unless the watch is silenced, so these are not
/// independent channels — the tone rides alongside to make the event unmistakable
/// in a noisy gym.
@MainActor
final class Feedback {

    /// The set was recognised. This lands at three reps, and it announces all three
    /// at once, so it has to be clearly distinct from a single rep tick — otherwise
    /// there is no way to tell "that was your third" from "that was one more".
    /// Two rising notes against the rep tick's single blip.
    func locked() {
        WKInterfaceDevice.current().play(.success)
        play(locked_)
    }

    /// One more rep. Deliberately the smallest thing available.
    ///
    /// This fires up to sixteen times in a set and once per rep for the whole
    /// workout. Anything with presence becomes irritating by rep eight, so it is the
    /// subtlest haptic watchOS offers and a 28 ms tick.
    func rep() {
        WKInterfaceDevice.current().play(.click)
        play(rep_)
    }

    /// The set closed and the count is final.
    func setEnded() {
        WKInterfaceDevice.current().play(.stop)
    }

    // MARK: - audio

    private var rep_: AVAudioPlayer?
    private var locked_: AVAudioPlayer?
    private var ready = false

    init() {
        rep_ = load("rep")
        locked_ = load("locked")
    }

    private func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()          // decode up front; the first rep should not be late
        return p
    }

    /// Activated lazily on first use rather than at launch: claiming the audio
    /// session before there is anything to play would interrupt whatever the user is
    /// listening to for the whole session, for nothing.
    private func activate() {
        guard !ready else { return }
        ready = true
        let s = AVAudioSession.sharedInstance()
        // `.playback` so a counted rep is still audible with the watch silenced, and
        // `.mixWithOthers` because people lift to music and ducking it every few
        // seconds would be worse than saying nothing.
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true, options: [])
    }

    private func play(_ player: AVAudioPlayer?) {
        guard let p = player else { return }
        activate()
        p.currentTime = 0
        p.play()
    }

    /// Hand the audio route back when the workout ends.
    func release() {
        guard ready else { return }
        ready = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
