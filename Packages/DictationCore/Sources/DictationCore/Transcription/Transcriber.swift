import Foundation

/// The transcription providers the user can choose from (R10).
public enum TranscriptionProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case openAICompatible
    case deepgram
    case elevenLabs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .deepgram: "Deepgram"
        case .elevenLabs: "ElevenLabs Scribe"
        }
    }

    /// Only the OpenAI-compatible provider lets the user edit its base URL.
    public var defaultBaseURL: URL {
        switch self {
        case .openAICompatible: URL(string: "https://api.openai.com/v1")!
        case .deepgram: URL(string: "https://api.deepgram.com/v1")!
        case .elevenLabs: URL(string: "https://api.elevenlabs.io/v1")!
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAICompatible: "gpt-transcribe"
        case .deepgram: "nova-3"
        case .elevenLabs: "scribe_v2"
        }
    }
}

/// Everything a transcriber needs for one request.
public struct TranscriptionConfig: Sendable, Equatable {
    public var provider: TranscriptionProviderID
    public var baseURL: URL
    public var model: String
    /// May be empty for local OpenAI-compatible servers.
    public var apiKey: String
    /// Dictionary terms already selected for this provider and model (`VocabularyHints`).
    public var hints: [String]

    public init(provider: TranscriptionProviderID, baseURL: URL, model: String, apiKey: String, hints: [String] = []) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.hints = hints
    }
}

/// Turns one recorded `.m4a` clip into English text (R11).
public protocol Transcriber: Sendable {
    /// Returns the trimmed transcript, or throws a `DictationError`.
    func transcribe(audioFile: URL) async throws -> String
}
