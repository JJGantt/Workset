import SwiftUI

struct CaptureView: View {
    @StateObject private var capture = CaptureManager()
    @State private var finished: [MotionSample] = []

    var body: some View {
        VStack(spacing: 10) {
            if capture.isRecording {
                Text(capture.elapsed, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(capture.sampleCount) samples")
                    .font(.caption2).foregroundStyle(.secondary)

                // Whether the app is actually being kept alive is the single thing
                // that decides if this recording is usable, so it is on screen the
                // whole time rather than discovered afterwards.
                Label(capture.keepAlive.isHolding ? "Protected" : "NOT PROTECTED",
                      systemImage: capture.keepAlive.isHolding ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(capture.keepAlive.isHolding ? .green : .red)

                Button("Stop") { Task { finished = await capture.stop() } }
                    .tint(.red)
            } else if let q = capture.quality {
                summary(q)
            } else {
                Button {
                    Task { await capture.start() }
                } label: {
                    Label("Start set", systemImage: "record.circle")
                }
                .tint(.green)
            }

            if let f = capture.lastFailure {
                Text(f).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("Capture")
    }

    @ViewBuilder
    private func summary(_ q: CaptureQuality) -> some View {
        VStack(spacing: 6) {
            if q.isDegraded {
                Text("\(Int(q.missingFraction * 100))% OF SET LOST")
                    .font(.caption.weight(.bold)).foregroundStyle(.red)
            } else {
                Text("Complete").font(.caption.weight(.bold)).foregroundStyle(.green)
            }
            Text("\(q.sampleCount) samples · \(q.effectiveHz, format: .number.precision(.fractionLength(0))) Hz")
                .font(.caption2).foregroundStyle(.secondary)
            Text("\(q.spanSeconds, format: .number.precision(.fractionLength(1)))s")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
