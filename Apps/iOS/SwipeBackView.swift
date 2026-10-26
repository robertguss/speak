import SwiftUI

struct SwipeBackView: View {
    let session: FlowSessionController
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if let error = session.startError {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text(error)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("Ready to dictate")
                    .font(.largeTitle.bold())
                Text("Swipe back to your app and tap the mic again.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Done", action: dismiss)
                .buttonStyle(.bordered)
        }
        .padding(32)
    }
}
