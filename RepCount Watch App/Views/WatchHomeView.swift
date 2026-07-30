import SwiftUI

struct WatchHomeView: View {
    var body: some View {
        NavigationStack {
            List {
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
