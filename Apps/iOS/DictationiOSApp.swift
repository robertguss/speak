import SwiftUI
import DictationUI

@main
struct DictationiOSApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Dictation")
            }
        }
    }
}
