import DictationCore
import DictationUI
import SwiftUI

@main
struct SpeakMacApp: App {
    @State private var controller: MacDictationController
    private let indicator: IndicatorPanel

    init() {
        ClipRecorder.purgeClips()
        let controller = MacDictationController()
        _controller = State(initialValue: controller)
        indicator = IndicatorPanel(controller: controller)
        controller.activateHotkey()
        NotificationCenter.default.addObserver(forName: SettingsModel.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { controller.activateHotkey() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { controller.activateHotkey() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            if let symbol = menuSymbol {
                Image(systemName: symbol)
            } else {
                Image("MenuBarIcon")
            }
        }

        Window("Set up Speak", id: "onboarding") {
            OnboardingView { controller.activateHotkey() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(OnboardingView.permissionsGranted ? .suppressed : .presented)

        Settings {
            SettingsView()
                .frame(width: 520, height: 620)
        }
    }

    /// A status symbol while busy or failed; nil shows the Speak wave.
    private var menuSymbol: String? {
        switch controller.phase {
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .message(_, true): "exclamationmark.triangle"
        default: nil
        }
    }
}

private struct MenuContent: View {
    let controller: MacDictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let error = controller.lastError {
            Text("Last error: \(error)")
            Divider()
        }
        if !controller.hotkeyActive {
            Text("Dictation key inactive: grant Accessibility")
        }
        Button("Set Up Permissions…") {
            NSApp.activate()
            openWindow(id: "onboarding")
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Speak") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
