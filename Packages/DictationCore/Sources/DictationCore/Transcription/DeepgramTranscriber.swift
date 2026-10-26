import Foundation

public struct DeepgramTranscriber: Transcriber {
    static let queryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    let config: TranscriptionConfig
    let session: URLSession

    public init(config: TranscriptionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func transcribe(audioFile: URL) async throws -> String {
        let query = [("model", config.model), ("smart_format", "true"), ("language", "en")]
            + config.hints.map { ("keyterm", $0) }
        var components = URLComponents(url: config.baseURL.appending(path: "listen"), resolvingAgainstBaseURL: false)
        // Strict encoding: `+` left raw would reach Deepgram as a space.
        components?.percentEncodedQueryItems = query.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed))
        }
        guard let url = components?.url else { throw DictationError.provider(status: 0, message: "Invalid Deepgram URL") }
        var request = TranscriptionHTTP.request(url: url)
        request.setValue("Token \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: audioFile)

        let json = try await TranscriptionHTTP.send(request, session: session)
        let results = json["results"] as? [String: Any]
        let channel = (results?["channels"] as? [[String: Any]])?.first
        let alternative = (channel?["alternatives"] as? [[String: Any]])?.first
        return try TranscriptionHTTP.transcript(alternative?["transcript"])
    }
}
