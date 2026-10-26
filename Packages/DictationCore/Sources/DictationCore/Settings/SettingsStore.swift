import Foundation

/// Reads and edits the synced preferences and API keys (R14, KTD7).
///
/// The preferences blob holds only fields the user explicitly edited. Each edit re-reads the
/// current blob, writes just the fields that changed, and keeps keys this build doesn't know,
/// so a fresh install or an older build never wipes settings made on another device.
public struct SettingsStore: Sendable {
    let preferences: any BlobStore
    let secrets: SecretStore

    public init(preferences: any BlobStore, secrets: SecretStore) {
        self.preferences = preferences
        self.secrets = secrets
    }

    public static func keychain(accessGroup: String = AppConstants.keychainAccessGroup) -> SettingsStore {
        SettingsStore(
            preferences: KeychainBlobStore(account: "preferences", accessGroup: accessGroup),
            secrets: SecretStore(blob: KeychainBlobStore(account: "api-keys", accessGroup: accessGroup))
        )
    }

    /// Current preferences, or defaults when nothing is stored or the item can't be read. Never writes.
    public func load() -> AppPreferences {
        (try? stored()) ?? AppPreferences()
    }

    /// Current preferences, or defaults when nothing is stored. Throws when the item exists but
    /// can't be read, so a dictation never falls back to the default provider's host.
    public func stored() throws -> AppPreferences {
        guard let data = try preferences.read() else { return AppPreferences() }
        return (try? JSONDecoder().decode(AppPreferences.self, from: data)) ?? AppPreferences()
    }

    /// Applies one explicit user edit and returns the resulting preferences.
    @discardableResult
    public func update(_ edit: (inout AppPreferences) -> Void) throws -> AppPreferences {
        var stored: [String: Any] = [:]
        if let data = try preferences.read() {
            stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let before = (try? JSONDecoder().decode(AppPreferences.self, from: JSONSerialization.data(withJSONObject: stored))) ?? AppPreferences()
        var after = before
        edit(&after)

        let oldFields = try Self.fields(of: before)
        let newFields = try Self.fields(of: after)
        for key in Set(oldFields.keys).union(newFields.keys) {
            let new = newFields[key]
            guard !Self.same(oldFields[key], new) else { continue }
            stored[key] = new
        }
        try preferences.write(JSONSerialization.data(withJSONObject: stored, options: [.sortedKeys]))
        return after
    }

    public func apiKey(_ role: KeyRole, baseURL: URL) -> String {
        secrets.value(for: SecretStore.name(for: role, baseURL: baseURL)) ?? ""
    }

    public func setAPIKey(_ key: String, role: KeyRole, baseURL: URL) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try secrets.setValue(trimmed, for: SecretStore.name(for: role, baseURL: baseURL))
    }

    /// The transcription request settings for the selected provider, with the key for its host.
    public func transcriptionConfig(_ prefs: AppPreferences) -> TranscriptionConfig {
        let provider = prefs.transcriptionProvider
        let baseURL = prefs.baseURL(for: provider)
        return TranscriptionConfig(
            provider: provider,
            baseURL: baseURL,
            model: prefs.model(for: provider),
            apiKey: apiKey(.transcription, baseURL: baseURL)
        )
    }

    private static func fields(of prefs: AppPreferences) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any] ?? [:]
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as AnyObject).isEqual(b)
        default: false
        }
    }
}
