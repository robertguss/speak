import Foundation

public struct OpenAICompatibleTranscriber: Transcriber {
    let config: TranscriptionConfig
    let session: URLSession

    public init(config: TranscriptionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func transcribe(audioFile: URL) async throws -> String {
        var form = Multipart()
        form.addFile("file", filename: "audio.m4a", contentType: "audio/mp4", data: try Data(contentsOf: audioFile))
        form.addField("model", config.model)
        form.addField(config.model.hasPrefix("gpt-transcribe") ? "languages[]" : "language", "en")

        var request = TranscriptionHTTP.request(
            url: config.baseURL.appending(path: "audio").appending(path: "transcriptions")
        )
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = form.finalized()

        let json = try await TranscriptionHTTP.send(request, session: session)
        return try TranscriptionHTTP.transcript(json["text"])
    }
}
