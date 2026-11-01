# Watchset: state of the app

What is built, how it ships, and what is still open. `README.md` describes the structure;
this file is the working detail.

| | |
|---|---|
| App Store name | **Watchset** ("Workset" was taken) |
| Naming rule | project, repo, bundle ids and targets are `Workset` (internal, invisible). Everything the user can see says Watchset: display name, navigation titles, permission strings. |
| Bundles | `com.jaredgantt.workset` (iPhone), `com.jaredgantt.workset.watchkitapp` (watch) |
| Counter | `RepCounter` product of a private Swift package, pinned by exact version in `project.yml` |

---

## Layout

```
Workset Watch App/   capture, workout keep-alive, counting loop, feedback, upload, UI
Workset/             iPhone carrier app (iPhone only; exists to embed the watch app)
Interface/           RepCounter.swiftinterface, the counter's public surface
```

The counter is platform-free and returns events rather than firing haptics, so the logic
the watch runs is the logic that is tested offline. `SessionCounter` deliberately holds no
counting decisions of its own.

---

## Releasing

Bump `CURRENT_PROJECT_VERSION` in `project.yml`, then, with an App Store Connect API key:

```bash
xcodegen generate
AUTH=(-allowProvisioningUpdates -authenticationKeyPath <AuthKey.p8>
      -authenticationKeyID <key id> -authenticationKeyIssuerID <issuer id>)
xcodebuild -project Workset.xcodeproj -scheme Workset -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/W.xcarchive "${AUTH[@]}" archive
xcodebuild -exportArchive -archivePath /tmp/W.xcarchive -exportPath /tmp/export \
  -exportOptionsPlist ExportOptions.plist "${AUTH[@]}"
xcrun altool --upload-app -f /tmp/export/Workset.ipa -t ios --apiKey <key id> --apiIssuer <issuer id>
```

**A build must then be attached to a beta group or it is invisible in TestFlight.**

Constraints, each of which has stopped a build:

- The **ASC API cannot create app records** (403, `apps does not allow CREATE`). That step is
  manual in the web UI. The API can create bundle ids and beta groups.
- Internal beta groups reject external tester records; create the tester against the
  internal group directly.
- **`UPLOAD SUCCEEDED` is not evidence that a build exists.** Apple can reject a build during
  processing (ITMS-90683), email the reason, and leave no trace in the API. Confirm the build
  registers.
- **Purpose strings belong on the PHONE target too**, although only the watch touches
  CoreMotion and HealthKit: Apple's static scan attributes the embedded watch binary's API
  use to the top-level bundle. That is what ITMS-90683 reports.
- **An app icon is mandatory** or the upload is rejected outright.
- Declaring iPad support obliges all four orientations for multitasking; the phone app is
  `TARGETED_DEVICE_FAMILY: "1"`.
- `ITSAppUsesNonExemptEncryption: NO` on both targets, or every upload stops for a
  compliance question.
- The watch target needs the HealthKit entitlement as well as the usage strings, or
  `requestAuthorization` fails and the session never starts.

---

## Data pipeline

The app ships a Supabase **publishable** key and acts as `anon`. What that key may do is
exactly what the app does:

| what | anon may |
|---|---|
| storage bucket `workset-captures` | INSERT `text/csv` at `workset/sensor_capture/<session>/motion.csv`, up to 20 MB. No read, overwrite or delete. |
| table `workset_reports` | INSERT `reps, occurred_at, session, algorithm`; UPDATE `corrected_reps, deleted` on recent rows |
| function `workset_watcher()` | call it: the armed exercise and weight, or nulls when nothing is armed |

Everything else is service-role only. Failed uploads queue on disk and retry, since the gym
is exactly where there is no signal; a file leaves the queue only on a 2xx or a 409 (already
stored).

**Every capture carries the verdict that produced it.** The metadata line holds the app's
count, the algorithm version, and where and when each rep was counted, so an old recording
says what the code of its day decided. Bump `AlgorithmVersion.current` in the counter
whenever a change could move a count.

**The `count` field stays 0.** That is the field the tooling reads as ground truth, and the
app's own guess landing there would make the counter its own ground truth. Scoring skips
`count == 0`, so a recording stays out of the numbers until it is labelled with what was
actually done.

The CSV is **all numeric**: the loader floats every column, so a text field is a crash.
Activity is a bitmask for that reason, and because CoreMotion's flags are not mutually
exclusive.

---

## Sets on the wrist

**Add set** enters a rep count on the crown and sends it through exactly the path a counted
set takes, so the armed exercise and weight are attached the same way. Offered only while
watching, not mid-count, so one piece of lifting cannot become two logged sets. The
algorithm field reads `manual`.

**Repeat** logs the last set's count again with one tap.

**Discard** rejects the set being counted without switching the session off; stopping the
session would clear the list of sets already done. The recording still uploads, marked
`app_cancelled,1`: a set the counter recognised and the lifter rejected is a labelled false
positive, and there is no other way to produce one.

**+ / −** correct a logged count and **✕** removes it. Both edit the report, which edits the
training log.

**Minimum set length.** An automatically detected set under **6 reps** is not logged.
Short real sets are entered by hand; the manual path exists so the automatic one can be
strict. Rejected detections still upload, marked `app_cancelled`. Pressing Stop applies the
same rule. Manual entry and repeat have no minimum.

---

## Open questions

- **Walking.** CoreMotion's activity classifier is recorded on every sample and gates
  nothing. It is not usable as a gate: real sets have logged `walking` at high confidence
  for most of their samples.
- **Small-range exercises** (shrugs, calf raises) barely move the wrist and are not counted.
- **Watch CPU and battery** during a long session are unmeasured on real hardware;
  `lastPassMs` is on screen for that.

---

## History

| build | what |
|---|---|
| 1 | first TestFlight upload; per-set Start button |
| 2 | always-on session: sets found inside a continuous stream |
| 3-4 | raw upload and stored verdicts, both rejected with ITMS-90683 |
| 5 | purpose strings added to the phone target |
| 6 | HealthKit entitlement; UI says Watchset |
| 7 | per-rep feedback, self-pacing passes |
| 8-13 | live announcement timing |
| 14 | spoken rep numbers (see `VOICE.md`) |
| 15 | pre-set stillness saved with every capture |
| 16 | counted sets reported to the training log, correctable from the wrist |
| 17 | watcher checked when the session starts |
| 18 | set end detection |
| 19-20 | manual entry, discard, repeat |
| 21 | minimum set length |
