import Foundation

public struct DeepgramTranscriber: Transcriber {
    let config: TranscriptionConfig
    let session: URLSession

    public init(config: TranscriptionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func transcribe(audioFile: URL) async throws -> String {
        let url = config.baseURL.appending(path: "listen").appending(queryItems: [
            URLQueryItem(name: "model", value: config.model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "language", value: "en"),
        ])
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
