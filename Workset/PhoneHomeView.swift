import SwiftUI

/// The phone side is a companion for now. The work happens on the watch, which is
/// where the wrist is.
struct PhoneHomeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 44))
            Text("Watchset")
                .font(.title2.weight(.semibold))
            Text("Start a set from the watch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
