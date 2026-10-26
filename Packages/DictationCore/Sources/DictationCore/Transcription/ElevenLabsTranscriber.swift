import Foundation

public struct ElevenLabsTranscriber: Transcriber {
    let config: TranscriptionConfig
    let session: URLSession

    public init(config: TranscriptionConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func transcribe(audioFile: URL) async throws -> String {
        var form = Multipart()
        form.addFile("file", filename: "audio.m4a", contentType: "audio/mp4", data: try Data(contentsOf: audioFile))
        form.addField("model_id", config.model)
        form.addField("language_code", "en")
        form.addField("tag_audio_events", "false")
        config.hints.forEach { form.addField("keyterms", $0) }

        var request = TranscriptionHTTP.request(url: config.baseURL.appending(path: "speech-to-text"))
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.httpBody = form.finalized()

        let json = try await TranscriptionHTTP.send(request, session: session)
        return try TranscriptionHTTP.transcript(json["text"])
    }
}
