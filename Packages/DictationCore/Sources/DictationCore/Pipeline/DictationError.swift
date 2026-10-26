import Foundation

/// Every way a dictation can fail, named by cause (R16).
/// `message` carries the provider's own error text when it sent one.
public enum DictationError: Error, Equatable, Sendable {
    case missingKey
    case settingsUnreadable
    case invalidKey(message: String?)
    case outOfCredits(message: String?)
    case rateLimited(message: String?)
    case tooLarge(message: String?)
    case provider(status: Int, message: String?)
    case network(message: String)
    case noSpeech
    case tooShort
    case microphoneUnavailable(message: String)

    /// A short sentence for the indicator, menu, or keyboard status line.
    public var userMessage: String {
        switch self {
        case .missingKey: "No API key. Add one in Dictation settings."
        case .settingsUnreadable: "Couldn't read Dictation settings. Try again."
        case .invalidKey(let message): Self.join("Invalid API key", message)
        case .outOfCredits(let message): Self.join("Out of credits", message)
        case .rateLimited(let message): Self.join("Rate limited. Try again in a moment", message)
        case .tooLarge(let message): Self.join("Recording too large", message)
        case .provider(let status, let message): Self.join("Provider error (\(status))", message)
        case .network(let message): Self.join("Network error", message)
        case .noSpeech: "No speech detected"
        case .tooShort: "Recording too short"
        case .microphoneUnavailable(let message): Self.join("Microphone unavailable", message)
        }
    }

    private static func join(_ cause: String, _ message: String?) -> String {
        guard let message, !message.isEmpty else { return cause }
        return "\(cause): \(message)"
    }
}
