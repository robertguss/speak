import Foundation

public struct DictationResult: Equatable, Sendable {
    public let text: String
    /// Cleanup was on but failed or was rejected, so `text` is the raw transcript.
    public let cleanupSkipped: Bool
}

/// Turns one recorded clip into final text: transcribe, optionally clean up, and always delete the clip.
public struct DictationPipeline: Sendable {
    public static let minimumClipDuration: TimeInterval = 0.5

    let settings: SettingsStore
    let session: URLSession
    let makeTranscriber: @Sendable (TranscriptionConfig) -> any Transcriber

    public init(
        settings: SettingsStore = .keychain(),
        session: URLSession = .shared,
        makeTranscriber: (@Sendable (TranscriptionConfig) -> any Transcriber)? = nil
    ) {
        self.settings = settings
        self.session = session
        self.makeTranscriber = makeTranscriber ?? { Transcribers.make(config: $0, session: session) }
    }

    public func run(clip: URL, duration: TimeInterval) async throws -> DictationResult {
        defer { try? FileManager.default.removeItem(at: clip) }
        guard duration >= Self.minimumClipDuration else { throw DictationError.tooShort }

        guard let prefs = try? settings.stored() else { throw DictationError.settingsUnreadable }
        var config = settings.transcriptionConfig(prefs)
        if config.apiKey.isEmpty && config.provider != .openAICompatible {
            throw DictationError.missingKey
        }
        // No host or key depends on the dictionary, so an unreadable one never fails the dictation (R12).
        let dictionary = (try? settings.dictionary.entries()) ?? []
        config.hints = VocabularyHints.select(dictionary, provider: config.provider, model: config.model).terms
        let raw = try await makeTranscriber(config).transcribe(audioFile: clip)
        let result = try await clean(raw, prefs: prefs, glossary: VocabularyHints.glossary(dictionary))
        return DictationResult(text: DictionaryReplacer.apply(to: result.text, entries: dictionary), cleanupSkipped: result.cleanupSkipped)
    }

    private func clean(_ raw: String, prefs: AppPreferences, glossary: [String]) async throws -> DictationResult {
        guard prefs.cleanupEnabled else { return DictationResult(text: raw, cleanupSkipped: false) }

        let cleanup = CleanupClient(
            config: CleanupConfig(
                baseURL: prefs.cleanupBaseURL,
                model: prefs.cleanupModel,
                apiKey: settings.apiKey(.cleanup, baseURL: prefs.cleanupBaseURL),
                prompt: prefs.cleanupPrompt ?? DefaultCleanupPrompt.text,
                glossary: glossary
            ),
            session: session
        )
        guard let cleaned = try? await cleanup.clean(raw), CleanupGuard.accepts(cleaned: cleaned, raw: raw) else {
            return DictationResult(text: raw, cleanupSkipped: true)
        }
        return DictationResult(text: cleaned, cleanupSkipped: false)
    }
}
