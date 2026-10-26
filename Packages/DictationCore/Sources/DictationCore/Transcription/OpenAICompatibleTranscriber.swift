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
        let keywords = VocabularyHints.usesKeywords(config.model)
        form.addField(keywords ? "languages[]" : "language", "en")
        if keywords {
            config.hints.forEach { form.addField("keywords[]", $0) }
        } else if !config.hints.isEmpty {
            form.addField("prompt", VocabularyHints.whisperPrompt(config.hints))
        }

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
