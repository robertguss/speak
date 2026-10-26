import AVFoundation
import ApplicationServices
import DictationCore
import SwiftUI

struct OnboardingView: View {
    let onAccessibilityGranted: () -> Void
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var trusted = AXIsProcessTrusted()
    @State private var hotkey = SettingsStore.keychain().load().macHotkey
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    static var permissionsGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && AXIsProcessTrusted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up Dictation").font(.title2.bold())

            step(
                done: micStatus == .authorized,
                title: "Microphone",
                detail: "Dictation records while you hold or tap the dictation key."
            ) {
                if micStatus == .notDetermined {
                    Button("Allow Microphone") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                        }
                    }
                } else {
                    Button("Open Microphone Settings") { open("Privacy_Microphone") }
                }
            }

            step(
                done: trusted,
                title: "Accessibility",
                detail: "Needed to listen for the dictation key and to paste text at the cursor."
            ) {
                Button("Open Accessibility Settings") {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                    open("Privacy_Accessibility")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dictation key: \(hotkey.displayName)").font(.headline)
                Text("Tap to start and tap again to stop, or hold while you talk. Change the key in Settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if hotkey == .fn {
                    Text("In System Settings → Keyboard, set \"Press 🌐 key to\" to \"Do Nothing\", so Fn doesn't also open the emoji picker or Apple Dictation.")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(poll) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            hotkey = SettingsStore.keychain().load().macHotkey
            let nowTrusted = AXIsProcessTrusted()
            if nowTrusted && !trusted { onAccessibilityGranted() }
            trusted = nowTrusted
        }
    }

    private func step(done: Bool, title: String, detail: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done { action() }
            }
        }
    }

    private func open(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
