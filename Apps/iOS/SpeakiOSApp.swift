import DictationCore
import DictationUI
import SwiftUI

@main
struct SpeakiOSApp: App {
    @State private var session: FlowSessionController
    @State private var showSwipeBack = false

    init() {
        ClipRecorder.purgeClips()
        _session = State(initialValue: FlowSessionController())
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SettingsView {
                    SessionSection(session: session) {
                        Task {
                            await session.start()
                            showSwipeBack = true
                        }
                    }
                }
                .navigationTitle("Speak")
            }
            .onOpenURL { url in
                guard url == AppConstants.startSessionURL else { return }
                Task {
                    await session.start()
                    showSwipeBack = true
                }
            }
            .fullScreenCover(isPresented: $showSwipeBack) {
                SwipeBackView(session: session) { showSwipeBack = false }
            }
        }
    }
}

private struct SessionSection: View {
    let session: FlowSessionController
    let start: () -> Void

    var body: some View {
        Section {
            if session.isActive {
                Label("Session active", systemImage: "mic.fill")
                    .foregroundStyle(.orange)
                Button("End session", role: .destructive) { session.end() }
            } else {
                Button("Start session", action: start)
            }
            if let error = session.lastError {
                Text("Last error: \(error)").foregroundStyle(.red)
            }
        } header: {
            Text("Keyboard session")
        } footer: {
            Text("Add the Speak keyboard in Settings → General → Keyboard → Keyboards, and turn on Allow Full Access. Tapping its mic starts a session here automatically.")
        }
    }
}
