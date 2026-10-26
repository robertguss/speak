import SwiftUI
import DictationUI

@main
struct DictationMacApp: App {
    var body: some Scene {
        MenuBarExtra("Dictation", systemImage: "mic") {
            Button("Quit Dictation") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView()
        }
    }
}
