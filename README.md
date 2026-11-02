# Watchset

An Apple Watch app that counts weightlifting reps from wrist motion. One switch covers the
whole workout: the watch streams device motion continuously, recognises a set when one
starts, counts it live with a haptic and a spoken number per rep, closes it when it ends,
reports the count, uploads the raw recording, and goes back to watching for the next set.

The project, repo, bundle ids and targets are named `Workset`; everything a user sees says
**Watchset**, the App Store name.

## How it is built

| path | what |
|---|---|
| `Workset Watch App/` | the watch app: motion capture, workout keep-alive, feedback, upload, UI |
| `Workset/` | the iPhone app, which exists to carry the watch app (iPhone only) |
| `Packages/SessionCore/` | the session loop around the counter, as a local package with its own tests |
| `Interface/RepCounter.swiftinterface` | the public surface of the rep counter the watch app links |
| `project.yml` | XcodeGen spec; `Workset.xcodeproj` is generated from it |

- **SwiftUI** on watchOS 11 and iOS 18, Swift 6 language mode. No third-party
  dependencies beyond the counter.
- **Capture.** `CaptureManager` reads CoreMotion device motion at 100 Hz in the
  `xMagneticNorthZVertical` frame, so yaw is an absolute heading. Each sample also carries
  CoreMotion's activity classification, recorded rather than acted on.
- **Staying alive.** watchOS suspends an app on wrist-down, which would lose most of a set.
  `WorkoutKeepAlive` runs an `HKWorkoutSession` with an actively collecting
  `HKLiveWorkoutBuilder`; a session whose collection never began does not keep motion
  delivery alive.
- **Counting.** `SessionLoop` (in SessionCore; the watch's `SessionCounter`) owns pacing,
  threading, the logged sets and published state, and hands the sample stream to the
  counter's `SessionMachine`, which returns events (set committed, rep count advanced, set
  closed). The counter lives in one actor and every operation on it, counting passes, Stop
  and Discard alike, runs there in order, so a button pressed mid-pass acts on what that
  pass left instead of being overwritten by it. Passes are self-pacing: the next starts
  when the previous one finishes, so cadence follows what the hardware can do.
- **Feedback.** `Feedback` plays a haptic on every rep, a chime when a set locks on, and
  pre-rendered spoken numbers (`Numbers/n1.wav` to `n50.wav`). See `VOICE.md`.
- **Reporting.** `SetReporter` posts each finished set (reps, time, algorithm version) to the
  data layer's `workset` edge function (`DataLayer`), which stores it as a report. The exercise and weight are not chosen on the watch: they are armed
  elsewhere, and a database trigger attaches them to the report. The watch asks the server
  what is armed so it can show whether sets are being logged, and can correct or remove a
  set it reported.
- **Recordings.** `CaptureUploader` saves every recognised set as a CSV and uploads it to a
  storage bucket, queueing on disk and retrying when there is no connection.
- **Manual entry.** Sets the wrist cannot see (leg press, seated movements) are entered on
  the crown and go through the same reporting path.

## Building

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Workset.xcodeproj -scheme Workset -destination 'generic/platform=iOS' build
```

Building needs read access to the counter package, which Swift Package Manager fetches
over SSH, and `Config/Secrets.xcconfig` (gitignored; copy `Config/Secrets.xcconfig.example`),
which holds the watch's device token. Without that file the build fails. Release and TestFlight steps are in `STATE.md`.

## Tests

```bash
cd Packages/SessionCore && swift test
```

SessionCore is tested against a scripted counter: a set found, counted, closed and logged
once; a rejected detection; manual entry; wrist edits; and Stop or Discard landing in the
middle of a counting pass. It does not depend on the private counter, so CI
(`.github/workflows/tests.yml`) runs it on every push.

## Algorithms

The rep counter is kept in a private package. This repository contains the interface the app calls it through.
