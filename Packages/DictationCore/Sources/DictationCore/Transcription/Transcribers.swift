import Foundation

public enum Transcribers {
    public static func make(config: TranscriptionConfig, session: URLSession = .shared) -> any Transcriber {
        switch config.provider {
        case .openAICompatible: OpenAICompatibleTranscriber(config: config, session: session)
        case .deepgram: DeepgramTranscriber(config: config, session: session)
        case .elevenLabs: ElevenLabsTranscriber(config: config, session: session)
        }
    }
}
