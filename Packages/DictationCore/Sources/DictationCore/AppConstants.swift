import Foundation

/// Identifiers shared by the Mac app, the iOS app, and the keyboard extension.
public enum AppConstants {
    /// App Group shared by the iOS app and its keyboard extension (KTD6).
    public static let appGroup = "group.com.robertguss.dictation"

    /// URL the keyboard opens to start a session in the iOS app (R7).
    public static let startSessionURL = URL(string: "dictation://start")!

    /// Team-prefixed keychain access group shared by every app (KTD7).
    /// `project.yml` writes it into each app's Info.plist so the team ID lives in one place.
    public static var keychainAccessGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "DictationKeychainAccessGroup") as? String ?? ""
    }
}
