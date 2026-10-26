import SwiftUI
import DictationCore

/// Holds the settings screen's copy of the synced preferences and keys.
/// Every change is an explicit edit written straight to the store (KTD7).
@MainActor
@Observable
public final class SettingsModel {
    /// Posted after a preference edit is saved, so the app can apply it right away.
    public static let didChange = Notification.Name("SettingsModel.didChange")

    public private(set) var prefs = AppPreferences()
    public private(set) var transcriptionKey = ""
    public private(set) var cleanupKey = ""
    public private(set) var saveError: String?
    private let store: SettingsStore

    public init(store: SettingsStore = .keychain()) {
        self.store = store
        reload()
    }

    /// Re-reads everything; there is no change notification for synced keychain items.
    public func reload() {
        prefs = store.load()
        reloadKeys()
    }

    public func edit(_ change: (inout AppPreferences) -> Void) {
        do {
            prefs = try store.update(change)
            saveError = nil
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        } catch {
            saveError = "Couldn't save settings: \(error)"
        }
        reloadKeys()
    }

    public func setKey(_ key: String, role: KeyRole) {
        let baseURL = role == .transcription ? prefs.baseURL(for: prefs.transcriptionProvider) : prefs.cleanupBaseURL
        do {
            try store.setAPIKey(key, role: role, baseURL: baseURL)
            saveError = nil
        } catch {
            saveError = "Couldn't save the API key: \(error)"
        }
        reloadKeys()
    }

    private func reloadKeys() {
        transcriptionKey = store.apiKey(.transcription, baseURL: prefs.baseURL(for: prefs.transcriptionProvider))
        cleanupKey = store.apiKey(.cleanup, baseURL: prefs.cleanupBaseURL)
    }
}

/// The shared settings screen. Apps put their own sections above the shared ones with `header`.
public struct SettingsView<Header: View>: View {
    @State private var model: SettingsModel
    @Environment(\.scenePhase) private var scenePhase
    private let header: Header

    public init(model: SettingsModel = SettingsModel(), @ViewBuilder header: () -> Header) {
        _model = State(initialValue: model)
        self.header = header()
    }

    public var body: some View {
        Form {
            header
            transcriptionSection
            cleanupSection
            platformSection
            if let error = model.saveError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
            Picker("Provider", selection: binding(\.transcriptionProvider)) {
                ForEach(TranscriptionProviderID.allCases) { Text($0.displayName).tag($0) }
            }
            let provider = model.prefs.transcriptionProvider
            if provider == .openAICompatible {
                Menu("Use preset") {
                    ForEach(OpenAICompatiblePreset.all) { preset in
                        Button(preset.name) {
                            model.edit {
                                $0.openAICompatibleBaseURL = preset.baseURL
                                $0.openAICompatibleModel = preset.model
                            }
                        }
                    }
                }
                URLField("Base URL", url: model.prefs.openAICompatibleBaseURL) { url in
                    model.edit { $0.openAICompatibleBaseURL = url }
                }
            }
            CommitField("Model", value: model.prefs.model(for: provider)) { value in
                model.edit { $0.setModel(value, for: provider) }
            }
            CommitField("API key", value: model.transcriptionKey, secure: true) { model.setKey($0, role: .transcription) }
                .id("transcription-key-\(model.prefs.baseURL(for: provider).host() ?? "")")
            if provider == .openAICompatible {
                Text("Leave the key empty for local servers that don't need one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cleanupSection: some View {
        Section {
            Toggle("Clean up with an LLM", isOn: binding(\.cleanupEnabled))
            if model.prefs.cleanupEnabled {
                URLField("Base URL", url: model.prefs.cleanupBaseURL) { url in
                    model.edit { $0.cleanupBaseURL = url }
                }
                CommitField("Model", value: model.prefs.cleanupModel) { value in
                    model.edit { $0.cleanupModel = value }
                }
                CommitField("API key", value: model.cleanupKey, secure: true) { model.setKey($0, role: .cleanup) }
                    .id("cleanup-key-\(model.prefs.cleanupBaseURL.host() ?? "")")
                PromptEditor(value: model.prefs.cleanupPrompt ?? DefaultCleanupPrompt.text) { value in
                    model.edit { $0.cleanupPrompt = value }
                }
                Button("Reset prompt to default") {
                    model.edit { $0.cleanupPrompt = nil }
                }
                .disabled(model.prefs.cleanupPrompt == nil)
            }
        } header: {
            Text("Cleanup")
        } footer: {
            Text("Sends the transcript to an OpenAI-compatible chat endpoint. For Claude, use OpenRouter's endpoint. If cleanup fails or changes the meaning, the raw transcript is used.")
        }
    }

    @ViewBuilder
    private var platformSection: some View {
        #if os(macOS)
        Section("Mac") {
            Picker("Dictation key", selection: binding(\.macHotkey)) {
                ForEach(MacHotkey.allCases) { Text($0.displayName).tag($0) }
            }
            if model.prefs.macHotkey == .fn {
                Text("In System Settings → Keyboard, set \"Press 🌐 key to\" to \"Do Nothing\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Section {
            Picker("End session after", selection: binding(\.idleTimeoutMinutes)) {
                ForEach(AppPreferences.idleTimeoutChoices, id: \.self) { Text("\($0) minutes idle").tag($0) }
            }
        } header: {
            Text("Keyboard session")
        } footer: {
            Text("The microphone stays ready in the background so the keyboard can dictate without opening the app.")
        }
        #endif
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(
            get: { model.prefs[keyPath: keyPath] },
            set: { value in model.edit { $0[keyPath: keyPath] = value } }
        )
    }
}

extension SettingsView where Header == EmptyView {
    public init(model: SettingsModel = SettingsModel()) {
        self.init(model: model) { EmptyView() }
    }
}

/// A text field that saves when the user submits or leaves it, not on every keystroke,
/// so typing doesn't push a keychain write per character.
private struct CommitField: View {
    let title: String
    let value: String
    let secure: Bool
    let onCommit: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(_ title: String, value: String, secure: Bool = false, onCommit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.secure = secure
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        Group {
            if secure {
                SecureField(title, text: $draft)
            } else {
                TextField(title, text: $draft)
            }
        }
        .focused($focused)
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .onSubmit(commit)
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: value) { _, newValue in
            if !focused { draft = newValue }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else { return }
        onCommit(trimmed)
    }
}

private struct URLField: View {
    let title: String
    let url: URL
    let onCommit: (URL) -> Void

    init(_ title: String, url: URL, onCommit: @escaping (URL) -> Void) {
        self.title = title
        self.url = url
        self.onCommit = onCommit
    }

    var body: some View {
        CommitField(title, value: url.absoluteString) { text in
            guard let url = URL(string: text), ["http", "https"].contains(url.scheme), url.host() != nil else { return }
            onCommit(url)
        }
        #if os(iOS)
        .keyboardType(.URL)
        #endif
    }
}

private struct PromptEditor: View {
    let value: String
    let onCommit: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(value: String, onCommit: @escaping (String) -> Void) {
        self.value = value
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Prompt")
            TextEditor(text: $draft)
                .font(.callout.monospaced())
                .frame(minHeight: 180)
                .focused($focused)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onChange(of: value) { _, newValue in
            if !focused { draft = newValue }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft != value else { return }
        onCommit(draft)
    }
}
