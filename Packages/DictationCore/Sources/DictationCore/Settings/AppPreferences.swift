import Foundation

/// The single modifier key that triggers dictation on the Mac (R1).
public enum MacHotkey: String, Codable, CaseIterable, Sendable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fn: "Fn / Globe"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        }
    }
}

/// Which API key a request needs. Keys are stored per role and host (KTD7).
public enum KeyRole: String, Sendable {
    case transcription
    case cleanup
}

/// User preferences synced through iCloud Keychain (R14).
/// Decoding is lenient: a missing or unreadable field falls back to its default,
/// so blobs written by older or newer builds always load.
public struct AppPreferences: Codable, Equatable, Sendable {
    public static let idleTimeoutChoices = [2, 5, 15]
    public static let defaultCleanupBaseURL = URL(string: "https://api.openai.com/v1")!
    public static let defaultCleanupModel = "gpt-6-luna"

    public var transcriptionProvider: TranscriptionProviderID = .openAICompatible
    public var openAICompatibleBaseURL: URL = TranscriptionProviderID.openAICompatible.defaultBaseURL
    public var openAICompatibleModel: String = TranscriptionProviderID.openAICompatible.defaultModel
    public var deepgramModel: String = TranscriptionProviderID.deepgram.defaultModel
    public var elevenLabsModel: String = TranscriptionProviderID.elevenLabs.defaultModel
    public var cleanupEnabled = false
    public var cleanupBaseURL: URL = Self.defaultCleanupBaseURL
    public var cleanupModel: String = Self.defaultCleanupModel
    /// `nil` means the built-in default prompt.
    public var cleanupPrompt: String?
    public var macHotkey: MacHotkey = .rightOption
    public var idleTimeoutMinutes = 5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        let defaults = AppPreferences()
        transcriptionProvider = value(.transcriptionProvider) ?? defaults.transcriptionProvider
        openAICompatibleBaseURL = value(.openAICompatibleBaseURL) ?? defaults.openAICompatibleBaseURL
        openAICompatibleModel = value(.openAICompatibleModel) ?? defaults.openAICompatibleModel
        deepgramModel = value(.deepgramModel) ?? defaults.deepgramModel
        elevenLabsModel = value(.elevenLabsModel) ?? defaults.elevenLabsModel
        cleanupEnabled = value(.cleanupEnabled) ?? defaults.cleanupEnabled
        cleanupBaseURL = value(.cleanupBaseURL) ?? defaults.cleanupBaseURL
        cleanupModel = value(.cleanupModel) ?? defaults.cleanupModel
        cleanupPrompt = value(.cleanupPrompt)
        macHotkey = value(.macHotkey) ?? defaults.macHotkey
        idleTimeoutMinutes = value(.idleTimeoutMinutes) ?? defaults.idleTimeoutMinutes
    }

    public func baseURL(for provider: TranscriptionProviderID) -> URL {
        provider == .openAICompatible ? openAICompatibleBaseURL : provider.defaultBaseURL
    }

    public func model(for provider: TranscriptionProviderID) -> String {
        switch provider {
        case .openAICompatible: openAICompatibleModel
        case .deepgram: deepgramModel
        case .elevenLabs: elevenLabsModel
        }
    }

    public mutating func setModel(_ model: String, for provider: TranscriptionProviderID) {
        switch provider {
        case .openAICompatible: openAICompatibleModel = model
        case .deepgram: deepgramModel = model
        case .elevenLabs: elevenLabsModel = model
        }
    }
}

/// Base URL and model presets for the OpenAI-compatible provider (KTD10).
public struct OpenAICompatiblePreset: Sendable, Identifiable {
    public let name: String
    public let baseURL: URL
    public let model: String
    public var id: String { name }

    public static let all = [
        OpenAICompatiblePreset(name: "OpenAI", baseURL: TranscriptionProviderID.openAICompatible.defaultBaseURL, model: TranscriptionProviderID.openAICompatible.defaultModel),
        OpenAICompatiblePreset(name: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!, model: "whisper-large-v3-turbo"),
    ]
}
