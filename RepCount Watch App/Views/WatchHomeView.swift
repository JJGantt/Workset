import SwiftUI

struct WatchHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CountView()
                } label: {
                    Label("Count reps", systemImage: "figure.strengthtraining.traditional")
                }
                // Records without counting — how new reference recordings get made.
                NavigationLink {
                    CaptureView()
                } label: {
                    Label("Record a set", systemImage: "waveform.path.ecg")
                }
            }
            .navigationTitle("RepCount")
        }
    }
}
