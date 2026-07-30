import SwiftUI

/// The live counter: start a set, and the number goes up on its own.
struct CountView: View {
    @StateObject private var capture = CaptureManager()
    @StateObject private var counter = LiveCounter()
    @State private var finalCount: Int?
    @State private var quality: CaptureQuality?

    var body: some View {
        VStack(spacing: 8) {
            if capture.isRecording {
                counting
            } else if let f = finalCount {
                finished(f)
            } else {
                Button {
                    Task {
                        finalCount = nil
                        await capture.start()
                        if capture.isRecording {
                            counter.start(snapshot: { [capture] in capture.snapshot() })
                        }
                    }
                } label: {
                    Label("Start set", systemImage: "figure.strengthtraining.traditional")
                }
                .tint(.green)
            }

            if let f = capture.lastFailure {
                Text(f).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Count")
    }

    private var counting: some View {
        VStack(spacing: 4) {
            // Before the algorithm commits there is genuinely no count to show.
            // Showing a 0 that later jumps
            // to 3 would read as the counter having missed them.
            Text(counter.isCommitted ? "\(counter.count)" : "–")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: counter.count)

            Text(counter.isCommitted ? "reps" : "finding your rhythm")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Whether the app is being kept alive decides whether any of this works,
            // so it stays on screen rather than being discovered afterwards.
            if !capture.keepAlive.isHolding {
                Label("NOT PROTECTED", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Button("Done") {
                Task {
                    counter.stop()
                    let samples = await capture.stop()
                    quality = capture.quality
                    // The authoritative count, taken once over the whole set. The
                    // live number could not revise itself downward; this one can.
                    finalCount = LiveCounter.count(samples)?.cycles ?? counter.count
                }
            }
            .tint(.red)
        }
    }

    private func finished(_ n: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(n)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
            Text("reps").font(.caption2).foregroundStyle(.secondary)
            if let q = quality, q.isDegraded {
                Text("\(Int(q.missingFraction * 100))% of the set was lost")
                    .font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button("New set") { finalCount = nil; quality = nil }
        }
    }
}
