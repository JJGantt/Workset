import SwiftUI

/// One switch for the whole workout.
///
/// Not a set timer — turn it on and leave it on. Sets are found inside the stream,
/// counted, closed when they end, and logged; then it re-arms for whatever comes
/// next, which may be a completely different exercise.
struct SessionView: View {
    @StateObject private var capture = CaptureManager()
    @StateObject private var session = SessionCounter()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch session.phase {
                case .off:      idle
                case .armed:    armed
                case .counting: counting
                }

                if !session.sets.isEmpty { log }

                if let f = capture.lastFailure {
                    Text(f).font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Workset")
    }

    private var idle: some View {
        Button {
            Task {
                await capture.start()
                if capture.isRecording {
                    session.begin(pull: { [capture] in capture.drain() })
                }
            }
        } label: {
            Label("Start", systemImage: "power")
        }
        .tint(.green)
    }

    private var armed: some View {
        VStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.variableColor.iterative)
            Text("watching")
                .font(.caption).foregroundStyle(.secondary)
            protection
            stopButton
        }
    }

    private var counting: some View {
        VStack(spacing: 2) {
            Text("\(session.count)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: session.count)
            Text("reps").font(.caption2).foregroundStyle(.secondary)
            protection
            stopButton
        }
    }

    /// Whether the app is being kept alive decides whether any of this works, so it
    /// is visible while it matters rather than discovered afterwards.
    @ViewBuilder
    private var protection: some View {
        if !capture.keepAlive.isHolding {
            Label("NOT PROTECTED", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.red)
        }
    }

    private var stopButton: some View {
        Button("Stop") {
            Task {
                session.end()
                _ = await capture.stop()
            }
        }
        .tint(.red)
        .font(.caption)
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            // Newest first — the set just finished is the one being checked.
            ForEach(Array(session.sets.enumerated().reversed()), id: \.offset) { _, s in
                HStack {
                    Text("\(s.count)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .frame(width: 34, alignment: .trailing)
                    Text("reps").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(s.duration))s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
